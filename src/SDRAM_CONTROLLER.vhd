-- TODO: Formally verify me!
-- TODO: Make me 2002 compatible!

-- fclk  Delayed write   clkref
--       CPU      VRAM  
--     ----------------------
-- 0     RAS      <DI>      0
-- 1                        0       
-- 2     READ     PRE       1   
-- 3                        1
-- 4     <DO>[AP]           1
-- 5     <DO>     RAS       1  
-- 6                        0
-- 7              WRITE<DI> 0

-- Check the timing diagrams of the memory you are using!

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

package my_types_pkg is
    -- Define a record type
      type wishbone_t is record
        addr  : std_ulogic_vector(31 downto 0); -- address
        wdata : std_ulogic_vector(31 downto 0); -- master write data
        rdata : std_ulogic_vector(31 downto 0); -- master read data
        we    : std_ulogic; -- write enable
        sel   : std_ulogic_vector(03 downto 0); -- byte enable
        stb   : std_ulogic; -- strobe
        cyc   : std_ulogic; -- valid cycle
        ack   : std_ulogic; -- transfer acknowledge
        err   : std_ulogic; -- transfer error
      end record;
end package my_types_pkg;

library IEEE;
library work;

use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
use work.my_types_pkg.all;
--use WORK.custom_functions_and_datatypes.ALL;

entity SDRAM_CONTROLLER is
    port(
      -- Debug pins
        o_SDRAM_READY   : out std_logic;
      -- SDRAM Side interface
        o_ADDR      : out std_logic_vector(11 downto 0);
        o_BS        : out std_logic_vector(1 downto 0) := "00";
        io_DQ       : inout std_logic_vector(15 downto 0);
        o_RASn      : out std_logic;
        o_CASn      : out std_logic;
        o_WEn       : out std_logic;
        o_CSn       : out std_logic;
        o_SDRAM_DQM : inout std_logic_vector(1 downto 0);
        i_CLK       : in std_logic;
        o_CKE       : out std_logic;
        resetn      : in std_logic := '1';

        -- CPU access (WISHBONE SLAVE interface)
        o_WB_CPU_ACK  : out std_ulogic;
        i_WB_CPU_ADDR : in  std_ulogic_vector( 31 downto 0 );
        i_WB_CPU_DAT  : in  std_ulogic_vector( 31 downto 0 );
        o_WB_CPU_DAT  : out std_ulogic_vector( 31 downto 0 ) := (others => '0');
        o_WB_CPU_RTY  : out std_ulogic;
        i_WB_CPU_SEL  : in  std_ulogic_vector( 3 downto 0 );
        i_WB_CPU_STB  : in  std_ulogic;
        i_WB_CPU_WE   : in  std_ulogic;
        i_WB_CPU_CYC  : in  std_ulogic; 

        -- Graphics controller access
        o_WB_GC_ACK  : out std_ulogic;
        i_WB_GC_ADDR : in  std_ulogic_vector( 31 downto 0 );
        i_WB_GC_DAT  : in  std_ulogic_vector( 31 downto 0 );
        o_WB_GC_DAT  : out std_ulogic_vector( 31 downto 0 ) := (others => '0');
        o_WB_GC_RTY  : out std_ulogic;
        i_WB_GC_SEL  : in  std_ulogic_vector( 3 downto 0 );
        i_WB_GC_STB  : in  std_ulogic;
        i_WB_GC_WE   : in  std_ulogic;
        i_WB_GC_CYC  : in  std_ulogic
    );

end SDRAM_CONTROLLER;

architecture behavior of SDRAM_CONTROLLER is 
    constant REFRESH_CYCLES : unsigned(9 downto 0) := to_unsigned(500, 10);
    constant FREQ : integer := 96_000_000;

    -- Counter threshold constants for each state
    constant PRECHARGE_ALL_CYCLES : integer := 3;
    constant AUTO_REFRESH_CYCLES  : integer := 4;
    constant SET_MODE_REG_CYCLES  : integer := 1;

    -- Defining SDRAM commands
    -- CS# RAS# CAS# WE#
    constant CMD_NOP          : std_logic_vector(3 downto 0) := "1111";
    constant CMD_SetModeReg   : std_logic_vector(3 downto 0) := "0000";
    constant CMD_BankActivate : std_logic_vector(3 downto 0) := "0011";
    constant CMD_Write        : std_logic_vector(3 downto 0) := "0100";
    constant CMD_Read         : std_logic_vector(3 downto 0) := "0101";
    constant CMD_AutoRefresh  : std_logic_vector(3 downto 0) := "0001";
    constant CMD_PreCharge    : std_logic_vector(3 downto 0) := "0010";

    type SDRAM_COMMAND is (NOP, SetModeReg, BankActivate, Write, Read, AutoRefresh, PreCharge);
    signal d_RAM_CMD : SDRAM_COMMAND;

    type SDRAM_STATE is (s_INIT_DELAY, s_SETUP, s_NORMAL);
    type SETUP_STATE is (s_PRECHARGE_ALL, s_AUTO_REFRESH1, s_AUTO_REFRESH2, s_SET_MODE_REG, s_INIT_CONFIG_DONE);
    type RW_STATE    is (WAITING_RW_OPERATION, REFRESHING, EXECUTING_ACTIVATE, EXECUTING_RW, FINISHING_RW);

    signal r_RW_STATE : RW_STATE := WAITING_RW_OPERATION;

    signal r_SDRAM_STATE : SDRAM_STATE := s_INIT_DELAY;
    signal r_SETUP_STATE : SETUP_STATE := s_PRECHARGE_ALL;

    signal RAM_CMD : std_logic_vector(3 downto 0) := CMD_NOP; -- Command register for RAM
    signal cfg_now : std_logic := '0'; -- 200 us flag signal

    signal cycle : unsigned(7 downto 0) := (others => '0');

    -- Helper signals?
    signal need_refresh : std_logic := '0';
    signal refresh_cnt  : unsigned(9 downto 0) := to_unsigned(501, 10);
    signal busy : std_logic := '0';
    signal rst_done, rst_done_q, i_WB_STB_q, i_WB_STB_qq, begin_RW : std_logic := '0';
    signal rst_cnt  : unsigned(31 downto 0) := (others => '0');
    signal dq_out, dq_in : std_logic_vector(io_DQ'length-1 downto 0);
    signal dq_oen : std_logic := '0';
    signal gc_dout_buff, cpu_dout_buff : std_logic_vector(31 downto 0);

    type std_logic_matrix is array (natural range <>) of std_logic_vector;
    signal din_next      : std_logic_matrix(0 to 1)(i_WB_CPU_DAT'length-1 downto 0);
    signal addr_next     : std_logic_matrix(0 to 1)(i_WB_CPU_ADDR'length-1 downto 0);
    signal ds_next       : std_logic_matrix(0 to 1)(3 downto 0);
    signal port_req_next : std_logic_vector(0 to 1) := (others => '0');
    signal we_next       : std_logic_vector(0 to 1) := (others => '0');
    signal oe_next       : std_logic_vector(0 to 1);
    signal ack_next      : std_logic_vector(0 to 1) := (others => '0');

    signal din_latch      : std_logic_matrix(0 to 1)(i_WB_CPU_DAT'length-1 downto 0);
    signal addr_latch     : std_logic_matrix(0 to 1)(i_WB_CPU_ADDR'length-1 downto 0);
    signal ds_latch       : std_logic_matrix(0 to 1)(3 downto 0);
    signal port_req_latch : std_logic_vector(0 to 1) := (others => '0');
    signal we_latch       : std_logic_vector(0 to 1) := (others => '0');
    signal oe_latch       : std_logic_vector(0 to 1);
    signal ack_latch      : std_logic_vector(0 to 1) := (others => '0');

    signal delayed_write : std_logic := '0';

    type wb_ports is array (natural range <>) of wishbone_t;
    signal controller_ports : wb_ports(0 to 1);

begin
    -- Wiring the wishbone ports
    o_WB_CPU_ACK              <= controller_ports(0).ack;
    controller_ports(0).addr  <= i_WB_CPU_ADDR; 
    o_WB_CPU_DAT              <= controller_ports(0).rdata; 
    controller_ports(0).wdata <= i_WB_CPU_DAT;
    controller_ports(0).sel   <= i_WB_CPU_SEL; 
    controller_ports(0).stb   <= i_WB_CPU_STB; 
    controller_ports(0).we    <= i_WB_CPU_WE; 
    controller_ports(0).cyc   <= i_WB_CPU_CYC; 

    o_WB_GC_ACK               <= controller_ports(1).ack;
    controller_ports(1).addr  <= i_WB_GC_ADDR; 
    o_WB_GC_DAT               <= controller_ports(1).rdata; 
    controller_ports(1).wdata <= i_WB_GC_DAT;
    controller_ports(1).sel   <= i_WB_GC_SEL; 
    controller_ports(1).stb   <= i_WB_GC_STB; 
    controller_ports(1).we    <= i_WB_GC_WE; 
    controller_ports(1).cyc   <= i_WB_GC_CYC; 


    o_SDRAM_READY <= '1' when r_SDRAM_STATE = s_NORMAL else
                     '0';

    -- Returning command names for debugging purposes
    process(RAM_CMD)
    begin
        case RAM_CMD is
            when "1111" =>
                d_RAM_CMD <= NOP;
            when "0000" =>
                d_RAM_CMD <= SetModeReg;
            when "0011" =>
                d_RAM_CMD <= BankActivate;
            when "0100" =>
                d_RAM_CMD <= Write;
            when "0101" =>
                d_RAM_CMD <= Read;
            when "0001" =>
                d_RAM_CMD <= AutoRefresh;
            when "0010" =>
                d_RAM_CMD <= PreCharge;
            when others =>
        end case;
    end process;

    -- I think that the ACK signal only lasts for like one clock cycle
    -- so I could get rid of the i_WB_*_CYC dependence for the latches
    -- Latch for the CPU ack signal
    wb_ack_gen: for i in 0 to 1 generate
        process(all)
        begin
            if controller_ports(i).cyc='1' and ack_latch(i)='1' then
                controller_ports(i).ack <= '1';
            elsif controller_ports(i).stb='0' then
                controller_ports(i).ack <= '0';
            end if;
        end process;
    end generate wb_ack_gen;

    -- Capturing GC and CPU
    wb_latching: for i in 0 to 1 generate
        process(controller_ports(i).cyc, ack_latch(i))
        begin
            port_req_next(i) <= '0';
            we_next(i)       <= '0';
            ds_next(i)       <= (others => '0'); 
            din_next(i)      <= (others => '0');
            addr_next(i)     <= (others => '0');

            if controller_ports(i).cyc and controller_ports(i).stb then
            -- Set request flag
                port_req_next(i) <= '1';
                we_next(i)       <= controller_ports(i).we;
                ds_next(i)       <= controller_ports(i).sel; 
                din_next(i)      <= controller_ports(i).wdata;
                addr_next(i)     <= controller_ports(i).addr;
                oe_next(i) <= not(we_next(i));
            end if;
        end process;
    end generate wb_latching;

    io_DQ <= dq_out when dq_oen ='1' else
             (others => 'Z');

    dq_in <= io_DQ;

    o_CKE <= '1';

    -- Wiring the command register
    o_CSn  <= RAM_CMD(3);
    o_RASn <= RAM_CMD(2);
    o_CASn <= RAM_CMD(1);
    o_WEn  <= RAM_CMD(0);
  
    process(i_CLK)
    begin   
        if rising_edge(i_CLK) then
            -- RAM Row refresh indicator
            if (refresh_cnt = 0) then
                need_refresh <= '0';
            elsif (refresh_cnt >= REFRESH_CYCLES) then
                need_refresh <= '1';
            end if;
        end if;
    end process;

    -- TODO: Add some logic for sending timeout errors


    -- SDRAM state machine
    STATE_MACHINE: process(i_CLK)
    -- This variable enables me to count the number of cycles I've been in a state
        variable v_CLK_CNT : unsigned(7 downto 0) := (others => '0');
    begin
        if rising_edge(i_CLK) then
            -- Controller logic
            if not(resetn) then
                busy          <= '1';
                o_SDRAM_DQM   <= "10";
                r_SDRAM_STATE <= s_INIT_DELAY;
            else 
                -- defaults
                o_SDRAM_DQM <= "00";
                RAM_CMD <= CMD_NOP; 

                case r_SDRAM_STATE is
                    when s_INIT_DELAY =>
                    -- waiting for 200 us on power-on and then go to setup state
                        if cfg_now then
                            r_SDRAM_STATE <= s_SETUP;
                            r_SETUP_STATE <= s_PRECHARGE_ALL;

                            -- Precharging all banks
                            RAM_CMD    <= CMD_PreCharge;
                            o_ADDR     <= (others => '0');
                            o_ADDR(10) <= '1';

                            v_CLK_CNT := (others => '0');
                        end if;

                    when s_SETUP =>
                    -- Issuing initial setup commands
                      case r_SETUP_STATE is
                        when s_PRECHARGE_ALL =>
                          if v_CLK_CNT = PRECHARGE_ALL_CYCLES then
                            r_SETUP_STATE <= s_AUTO_REFRESH1;
                            RAM_CMD <= CMD_AutoRefresh;
                            v_CLK_CNT := (others => '0');
                          else
                            v_CLK_CNT := v_CLK_CNT + 1;
                          end if;
                          
                        when s_AUTO_REFRESH1 =>
                          if v_CLK_CNT = AUTO_REFRESH_CYCLES then
                            r_SETUP_STATE <= s_AUTO_REFRESH2;
                            RAM_CMD <= CMD_AutoRefresh;
                            v_CLK_CNT := (others => '0');
                          else
                            v_CLK_CNT := v_CLK_CNT + 1;
                          end if;

                        when s_AUTO_REFRESH2=>
                          if v_CLK_CNT = AUTO_REFRESH_CYCLES then
                            r_SETUP_STATE <= s_SET_MODE_REG;
                            RAM_CMD <= CMD_SetModeReg;

                            -- Setting the RAM mode before continuing
                            o_ADDR <= (others => '0'); -- zeroing everything
                            o_ADDR(2 downto 0) <= "001"; -- burst length=2
                            o_ADDR(3) <= '0'; -- sequential addressing
                            o_ADDR(6 downto 4) <= "010"; -- CAS 2
                            o_ADDR(9) <= '0';

                            v_CLK_CNT := (others => '0');
                          else
                            v_CLK_CNT := v_CLK_CNT + 1;
                          end if;

                        when s_SET_MODE_REG =>
                          if v_CLK_CNT = SET_MODE_REG_CYCLES then
                            r_SETUP_STATE <= s_INIT_CONFIG_DONE; 
                            v_CLK_CNT := (others => '0');
                          else
                            v_CLK_CNT := v_CLK_CNT + 1;
                          end if;

                        when s_INIT_CONFIG_DONE =>
                          r_SDRAM_STATE <= s_NORMAL;
                          busy <= '0';
                          r_SETUP_STATE <= s_PRECHARGE_ALL;

                        when others =>

                      end case;

                    when s_NORMAL =>
                        -- Updating the refresh_cnt
                        if refresh_cnt<= REFRESH_CYCLES then 
                            refresh_cnt <= refresh_cnt + 1;
                        end if;

                        -- Check for delay Delayed write condition
                        RAM_CMD <= CMD_NOP; -- Default RAM command
                        dq_oen <= '0';
                        ack_latch <= "00";

                        -- It could be that you can only get here whenever there's a port request
                        case cycle is
                            when to_unsigned(0, cycle'length) => -- 0
                                -- Check if we need some delayed_write
                                if we_next="01" and port_req_next="11" then
                                    delayed_write <= '1';
                                else
                                    delayed_write <= '0';
                                end if;

                                -- Latching CPU and GC access related signals
                                for i in 0 to 1 loop
                                    din_latch(i)      <= din_next(i);
                                    addr_latch(i)     <= addr_next(i);
                                    ds_latch(i)       <= ds_next(i);
                                    port_req_latch(i) <= port_req_next(i);
                                    we_latch(i)       <= we_next(i);
                                    oe_latch(i)       <= oe_next(i);
                                end loop;

                                -- CPU RAS
                                o_ADDR <= "010"&addr_next(0)(8 downto 0);  --0000 0000 0000
                                o_BS   <= "00";

                                -- TODO: add condition here to signal whether
                                -- or not a port request has been made and is going
                                -- to be processed in the next cycles
                                if port_req_next(0) = '1' then
                                    RAM_CMD <= CMD_BankActivate;
                                end if;

                            when to_unsigned(1, cycle'length) => -- 1
                                if not(delayed_write) then
                                -- GC RAS
                                    o_ADDR <= "010"&addr_latch(1)(8 downto 0);
                                    o_BS   <= "01";
                                    if port_req_latch(1) = '1' then
                                        RAM_CMD <= CMD_BankActivate;
                                    end if;
                                else
                                -- NOP
                                end if;

                            when to_unsigned(2, cycle'length) => -- 2
                                if we_latch(0) = '1' and port_req_latch(0)='1' then
                                    dq_oen <= '1';
                                end if;

                                -- CPU R/W
                                o_ADDR <= "010"&addr_latch(0)(8 downto 0);
                                o_BS <= "00";
                                if port_req_latch(0) = '1' then
                                    if  we_latch(0)='1' then
                                        RAM_CMD <= CMD_Write;
                                        if we_latch(0)='1' then
                                            dq_out  <= din_latch(0)(31 downto 16);
                                        end if;
                                    else
                                        RAM_CMD <= CMD_Read;
                                    end if;
                                end if;

                            when to_unsigned(3, cycle'length) => -- 3
                                if we_latch(0) = '1' and port_req_latch(0)='1' then
                                    dq_oen <= '1';
                                end if;

                                if not(delayed_write) then
                                    -- CPU data
                                    if we_latch(0)='1' then
                                        ack_latch(0) <= '1';
                                        dq_out  <= din_latch(0)(15 downto 0);
                                    end if;

                                else
                                    -- GC RAS
                                    o_ADDR <= "010"&addr_latch(1)(8 downto 0);
                                    o_BS   <= "01";
                                    if port_req_next(1) = '1' then
                                        RAM_CMD <= CMD_BankActivate;
                                    end if;
                                end if;

                            when to_unsigned(4, cycle'length) => -- 4
                                if we_latch(0) = '0' and port_req_latch(0)='1' then
                                    controller_ports(0).rdata(15 downto 0) <= dq_in;
                                end if;

                                if not(delayed_write) then
                                    -- GC access
                                    o_ADDR <= "010"&addr_latch(1)(8 downto 0);
                                    o_BS   <= "01";
                                    if we_latch(1) = '1' and port_req_latch(1)='1' then
                                        dq_oen <= '1';
                                    end if;

                                    if port_req_latch(1) = '1' then 
                                        if we_latch(1) = '1' then
                                            RAM_CMD <= CMD_Write; 
                                            dq_out <=din_latch(1)(31 downto 16);
                                        else
                                            RAM_CMD <= CMD_Read;
                                        end if;

                                    end if;
                                else
                                    -- CPU <LZ>
                                end if;

                                if  port_req_latch(0) = '1' and we_latch(0) = '0' then
                                    cpu_dout_buff(31 downto 16) <= dq_in;
                                end if;

                            when to_unsigned(5, cycle'length) => -- 5
                                if we_latch(0) = '0' and port_req_latch(0)='1' then
                                    controller_ports(0).rdata(31 downto 16) <= dq_in;
                                end if;

                                -- CPU DATA
                                if port_req_latch(0) = '1' and we_latch(0) = '0' then
                                    cpu_dout_buff(15 downto 0) <= dq_in;
                                    ack_latch(0) <= '1';
                                end if;

                                if not(delayed_write) then
                                    -- CPU DATA

                                    -- GC Data
                                    if  we_latch(1) = '1' and port_req_latch(1)='1' then
                                        dq_oen <= '1';
                                    end if;

                                    if port_req_latch(1) = '1' and  we_latch(1) = '1' then
                                        -- Finishing writing on bank 1
                                        dq_out <=din_latch(1)(15 downto 0);
                                        ack_latch(1) <= '1';
                                    end if;
                                else
                                end if;

                                if port_req_latch(0) = '1' and we_latch(0) = '0' then
                                    cpu_dout_buff(15 downto 0) <= dq_in;
                                    ack_latch(0) <= '1';
                                end if;

                                -- TODO: Find a way so this register isn't rewriten during the 
                                -- writing of cpu_dout_buff
                                if port_req_latch(1) = '1' and we_latch(1) = '0' then
                                    gc_dout_buff(31 downto 16) <= dq_in;
                                end if;

                            when to_unsigned(6, cycle'length) => -- 6
                                -- CPU DATA
                                if port_req_latch(0) = '1' and we_latch(0) = '0' then
                                    ack_latch(0) <= '1';
                                end if;

                                if not(delayed_write) then
                                    -- GC DATA
                                    if port_req_latch(1) = '1' then
                                        --gc_dout_buff(31 downto 16) <= dq_in when we_latch(1) = '0';
                                    end if;
                                else
                                end if;

                                if port_req_latch(1) = '1' and we_latch(1) = '0' then
                                    gc_dout_buff(31 downto 16) <= dq_in;
                                end if;

                                if we_latch = "10" and port_req_latch(0) = '1' and port_req_latch(1) = '1' and we_latch(1) = '0' then
                                    gc_dout_buff(15 downto 0) <= dq_in;
                                    ack_latch(1) <= '1';
                                end if;

                            when to_unsigned(7, cycle'length) => -- 7
                                if not(delayed_write) then
                                -- NOP
                                else
                                    -- VRAM access
                                    o_ADDR  <= "010"&addr_latch(1)(8 downto 0);
                                    dq_out  <= din_latch(1)(15 downto 0); -- Writing port 2 data

                                    if port_req_latch(1) = '1' then
                                        RAM_CMD <= CMD_Write;
                                        if we_latch(1) = '1' then
                                            dq_oen <= '1';
                                        end if;
                                    end if;

                                end if;

                                if port_req_latch(1) = '1' and we_latch(1) = '0' then
                                    gc_dout_buff(15 downto 0) <= dq_in;
                                    ack_latch(1) <= '1';
                                end if;

                            when to_unsigned(8, cycle'length) => -- 8
                                if not(delayed_write) then
                                -- NOP
                                else
                                    if we_latch(1) = '1' and port_req_latch(1)='1' then
                                        dq_oen <= '1';
                                    end if;

                                    ack_latch(1) <= '1';
                                    dq_out <= din_latch(1)(31 downto 16); -- Writing port 2 data
                                end if;
                            when to_unsigned(9, cycle'length) => -- 9
                                if not(delayed_write) then
                                -- NOP
                                else
                                -- VRAM AP
                                end if;
                            when to_unsigned(10, cycle'length) => -- 10
                                if not(delayed_write) then
                                -- NOP
                                else
                                -- NOP
                                end if;
                            when to_unsigned(11, cycle'length) => -- 11
                                if not(delayed_write) then
                                    -- NOP
                                else
                                    -- NOP
                                end if;
                            when to_unsigned(12, cycle'length) => -- 11
                                if not(delayed_write) then
                                    -- NOP
                                else
                                    -- NOP
                                    delayed_write <= '0';
                                end if;
                            when others =>
                        end case;

                        -- Cycle counting logic
                        cycle <= cycle + 1;
                        if delayed_write then
                            if cycle = 12 then
                                cycle <= (others => '0');
                            end if;
                        else
                            if cycle = 7 then
                                cycle <= (others => '0');
                            end if;
                        end if;

                    when others =>
                end case;
            end if;
        end if;
    end process STATE_MACHINE;
      
    --
    -- Generate cfg_now pulse after initialization delay (normally 200us)
    --

    INIT_DELAY: process(i_CLK)
    begin
        if rising_edge(i_CLK) then
            if not(resetn) then
                rst_cnt  <= (others => '0');
                rst_done <= '0';
            else
                rst_done_q <= rst_done;
                cfg_now    <= rst_done and not(rst_done_q);

                -- this is for counting the reset time of the ram
                if (rst_cnt /= FREQ / 1000 * 2 / 1000) then
                    rst_cnt <= rst_cnt + 1;
                    rst_done <= '0';
                else
                    rst_done <= '1';
                end if;
            end if;
        end if;
    end process INIT_DELAY;

end behavior;
