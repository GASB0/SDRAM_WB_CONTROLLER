library IEEE;
library work;

use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
--use WORK.custom_functions_and_datatypes.ALL;

entity SDRAM_CONTROLLER is
    port(
      -- SDRAM Side interface
        o_ADDR : out std_logic_vector(12 downto 0);
        o_BS   : out std_logic_vector(1 downto 0);
        io_DQ  : inout std_logic_vector(15 downto 0);
        o_RASn : out std_logic;
        o_CASn : out std_logic;
        o_WEn  : out std_logic;
        o_CSn  : out std_logic;
        SDRAM_DQM: inout std_logic_vector(1 downto 0);
        i_CLK  : in std_logic;
        i_CKE  : out std_logic;
        resetn : in std_logic;

        -- CPU access (WISHBONE SLAVE interface)
        o_WB_ACK  : out std_ulogic;
        i_WB_CLK  : in  std_ulogic;
        i_WB_ADDR : in  std_ulogic_vector( 31 downto 0 );
        i_WB_DAT  : in  std_ulogic_vector( 31 downto 0 );
        o_WB_DAT  : out std_ulogic_vector( 31 downto 0 ) := (others => '0');
        i_WB_RST  : in  std_ulogic;
        i_WB_SEL  : in  std_ulogic_vector( 3 downto 0 );
        i_WB_STB  : in  std_ulogic;
        i_WB_WE   : in  std_ulogic;
        i_WB_CYC  : in  std_ulogic

    );
end SDRAM_CONTROLLER;

architecture behavior of SDRAM_CONTROLLER is 
    constant REFRESH_CYCLES : unsigned(9 downto 0) := to_unsigned(500, 10);
    constant FREQ : integer := 100_000_000;

    -- Counter threshold constants for each state
    constant PRECHARGE_ALL_CYCLES : integer := 3;
    constant AUTO_REFRESH_CYCLES  : integer := 5;
    constant SET_MODE_REG_CYCLES  : integer := 3;

    -- Defining SDRAM commands
    -- CS# RAS# CAS# WE#
    constant CMD_NOP          : std_logic_vector(3 downto 0) := "1111";
    constant CMD_SetModeReg   : std_logic_vector(3 downto 0) := "0000";
    constant CMD_BankActivate : std_logic_vector(3 downto 0) := "0011";
    constant CMD_Write        : std_logic_vector(3 downto 0) := "0100";
    constant CMD_Read         : std_logic_vector(3 downto 0) := "0101";
    constant CMD_AutoRefresh  : std_logic_vector(3 downto 0) := "0001";
    constant CMD_PreCharge    : std_logic_vector(3 downto 0) := "0010";

    type SDRAM_STATE is (s_INIT_DELAY, s_SETUP, s_NORMAL);
    type SETUP_STATE is (s_PRECHARGE_ALL, s_AUTO_REFRESH1, s_AUTO_REFRESH2, s_SET_MODE_REG, s_INIT_CONFIG_DONE);
    type RW_STATE is (WAITING_RW_OPERATION, REFRESHING, EXECUTING_RW, FINISHING_RW);

    signal r_RW_STATE : RW_STATE := WAITING_RW_OPERATION;

    signal r_SDRAM_STATE : SDRAM_STATE := s_INIT_DELAY;
    signal r_SETUP_STATE : SETUP_STATE := s_PRECHARGE_ALL;

    signal RAM_CMD : std_logic_vector(3 downto 0); -- Command register for RAM
    signal cfg_now : std_logic := '0'; -- 200 us flag signal

    -- Helper signals?
    signal need_refresh : std_logic := '0';
    signal refresh_cnt  : unsigned(9 downto 0) := to_unsigned(501, 10);
    signal busy : std_logic := '0';
    signal rst_done, rst_done_q, i_WB_STB_q, begin_RW : std_logic := '0';
    signal rst_cnt  : unsigned(31 downto 0) := (others => '0');
    signal dq_oen : std_logic := '0';
    signal dq_out : std_logic_vector(io_DQ'length-1 downto 0);

    signal din_latch  : std_logic_vector(i_WB_DAT'length-1 downto 0);
    signal addr_latch : std_logic_vector(i_WB_ADDR'length-1 downto 0);
    signal we_latch   : std_logic := '0';
begin

    -- Inferred Latch for the ACK signal
    o_WB_ACK <= '0' when i_WB_STB = '0' else
                '1' when r_RW_STATE = FINISHING_RW;

    io_DQ <= (others => 'Z') when dq_oen = '1' else
             dq_out;

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

    -- SDRAM state machine
    STATE_MACHINE: process(i_CLK)
    -- This variable enables me to count the number of cycles I've been in a state
        variable v_CLK_CNT : unsigned(7 downto 0) := (others => '0');
    begin
        if rising_edge(i_CLK) then
            -- Controller logic
            if not(resetn) then
                busy          <= '1';
                dq_oen        <= '1';
                SDRAM_DQM     <= "10";
                r_SDRAM_STATE <= s_INIT_DELAY;
            else 
                -- defaults
                dq_oen <= '1';
                SDRAM_DQM <= "11";
                RAM_CMD <= CMD_NOP; 

                case r_SDRAM_STATE is
                    when s_INIT_DELAY =>
                    -- waiting for 200 us on power-on and then go to setup state
                        if cfg_now then
                            r_SDRAM_STATE <= s_SETUP;
                            r_SETUP_STATE <= s_PRECHARGE_ALL;
                            RAM_CMD <= CMD_PreCharge;
                            v_CLK_CNT := (others => '0');
                        end if;

                    when s_SETUP =>
                    -- Issuing initial setup commands
                      case r_SETUP_STATE is
                        when s_PRECHARGE_ALL =>
                          if v_CLK_CNT = 2 then
                            r_SETUP_STATE <= s_AUTO_REFRESH1;
                            RAM_CMD <= CMD_AutoRefresh;
                            v_CLK_CNT := (others => '0');
                          else
                            v_CLK_CNT := v_CLK_CNT + 1;
                          end if;
                          
                        when s_AUTO_REFRESH1 =>
                          if v_CLK_CNT = 2 then
                            r_SETUP_STATE <= s_AUTO_REFRESH2;
                            RAM_CMD <= CMD_AutoRefresh;
                            v_CLK_CNT := (others => '0');
                          else
                            v_CLK_CNT := v_CLK_CNT + 1;
                          end if;

                        when s_AUTO_REFRESH2=>
                          if v_CLK_CNT = 2 then
                            r_SETUP_STATE <= s_SET_MODE_REG;
                            RAM_CMD <= CMD_SetModeReg;
                            v_CLK_CNT := (others => '0');
                          else
                            v_CLK_CNT := v_CLK_CNT + 1;
                          end if;

                        when s_SET_MODE_REG =>
                          if v_CLK_CNT = 2 then
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
                        refresh_cnt <= refresh_cnt + 1 when refresh_cnt<= REFRESH_CYCLES;

                        -- RW logic
                        case r_RW_STATE is
                          when WAITING_RW_OPERATION =>
                            -- Refresh logic
                            if need_refresh='1' and i_WB_CYC='0' then
                              refresh_cnt <= to_unsigned(0, refresh_cnt'length);
                              RAM_CMD <= CMD_AutoRefresh;
                              r_RW_STATE <= REFRESHING;
                            -- RW operations logic
                            elsif begin_RW='1' then
                              RAM_CMD <= CMD_Write when i_WB_WE='1' else
                                         CMD_Read;         
                              if i_WB_WE = '1' then
                                dq_oen <= '0';
                                dq_out <= din_latch(dq_out'length-1 downto 0);
                              end if;
                              o_ADDR <= "0010"&addr_latch(9 downto 1); -- Autoprecharged
                              o_BS <= "00";
                              r_RW_STATE <= EXECUTING_RW;
                            end if;

                          when REFRESHING =>
                            if v_CLK_CNT = 2 then
                              r_RW_STATE <= WAITING_RW_OPERATION;
                              v_CLK_CNT := (others => '0');
                            else
                              v_CLK_CNT := v_CLK_CNT + 1;
                            end if;           

                          when EXECUTING_RW =>
                            if v_CLK_CNT = 2 then
                              r_RW_STATE <= FINISHING_RW;
                              v_CLK_CNT := (others => '0');
                            else
                              v_CLK_CNT := v_CLK_CNT + 1;
                            end if;           

                          when FINISHING_RW =>
                            -- write the retrieved data in the output port
                            r_RW_STATE <= WAITING_RW_OPERATION;
                          when others =>
                        end case;

                    when others =>
                end case;
            end if;
        end if;
    end process STATE_MACHINE;
      
    --
    -- Capturing input signals
    --
    process(i_CLK)
      variable v_begin_RW : std_logic := '0';
    begin
        if rising_edge(i_CLK) then
          i_WB_STB_q <= i_WB_STB;
          v_begin_RW := i_WB_STB and not(i_WB_STB_q);
          begin_RW <= '0' when r_RW_STATE = WAITING_RW_OPERATION;

          -- this is the section to get all the latches to their default values
          if i_WB_CYC='0' then
            addr_latch <= (others => '0');
            din_latch  <= (others => '0');
            we_latch   <= '0';
          end if;

          -- detect when chip is accessed and latch data from the ports
          if v_begin_RW then
            begin_RW   <= '1';
            addr_latch <= i_WB_ADDR;
            din_latch  <= i_WB_DAT;
            we_latch   <= i_WB_WE;
          end if;
        end if;
    end process;

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
                cfg_now    <= rst_done and not(rst_done_q); -- Rising Edge Detect

                if (rst_cnt /= FREQ / 1000 * 200 / 1000) then
                    rst_cnt <= rst_cnt + 1;
                    rst_done <= '0';
                else
                    rst_done <= '1';
                end if;
            end if;
        end if;
    end process INIT_DELAY;

end behavior;
