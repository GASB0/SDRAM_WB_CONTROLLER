library IEEE;
library work;

use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

library neorv32;
use neorv32.neorv32_package.all;

entity DISP_CONTROLLER is 
    port(
        i_clk     : in std_ulogic;
        -- This is the port that goes into the CPU bus
        o_WB_CPU_ACK  : out std_ulogic;
        o_WB_CPU_ERR  : out std_ulogic := '0';
        i_WB_CPU_ADDR : in  std_ulogic_vector( 31 downto 0 );
        i_WB_CPU_DAT  : in  std_ulogic_vector( 31 downto 0 );
        o_WB_CPU_DAT  : out std_ulogic_vector( 31 downto 0 );
        o_WB_CPU_RTY  : out std_ulogic;
        i_WB_CPU_SEL  : in  std_ulogic_vector( 3 downto 0 );
        i_WB_CPU_STB  : in  std_ulogic;
        i_WB_CPU_WE   : in  std_ulogic;
        i_WB_CPU_CYC  : in  std_ulogic;

        -- This is the port that goes into the SDRAM controller
        i_WB_SDRAM_ACK  : in   std_ulogic;
        i_WB_SDRAM_ERR  : in   std_ulogic := '0';
        o_WB_SDRAM_ADDR : out  std_ulogic_vector( 31 downto 0 );
        i_WB_SDRAM_DAT  : in   std_ulogic_vector( 31 downto 0 );
        o_WB_SDRAM_DAT  : out  std_ulogic_vector( 31 downto 0 );
        i_WB_SDRAM_RTY  : in   std_ulogic;
        o_WB_SDRAM_SEL  : out  std_ulogic_vector( 3 downto 0 );
        o_WB_SDRAM_STB  : out  std_ulogic;
        o_WB_SDRAM_WE   : out  std_ulogic;
        o_WB_SDRAM_CYC  : out  std_ulogic
        );
end DISP_CONTROLLER;

architecture behavior of DISP_CONTROLLER is
    -- Base addresses and sizes
    constant sdram_dc_base_addr_c  : std_ulogic_vector(31 downto 0) := x"B0000000"; -- wishbone memory base address (default begin of EXTERNAL IO area)
    constant sdram_dc_size_c       : natural := 8*1024; -- wishbone memory size in bytes, should be smaller than an iCACHE block

    type CONTROLLER_STATE is     (VRAM_WRITE, VRAM_READ);
    type WB_TRANSMISION_STATE is (WAITING_ACK, IDLE, RW_DATA, SENDING_DATA , FINISH_TRASACTION);

    signal r_WB_TRANSMISION : WB_TRANSMISION_STATE := IDLE;
    signal SDRAM_ACK_RECEIVED, qi_WB_SDRAM_ACK : std_ulogic;
    signal qi_WB_CPU_CYC : std_ulogic;
    signal BRAM_WRITE_BUFFER : std_ulogic_vector(31 downto 0);
    signal cpu_rw_op_req, cpu_rw_op_req_next, we_next, we_latch, port_req_latch : std_ulogic := '0';
    signal addr_latch, addr_next, din_latch, din_next    : std_ulogic_vector(31 downto 0) := (others => '0');

    signal ds_latch, ds_next : std_ulogic_vector(3 downto 0)  := (others => '0'); 

    signal base_addresses    : std_ulogic_vector(31 downto 0) := sdram_dc_base_addr_c;
    signal valid_ram_address : std_ulogic;

    signal dummy_cnt : unsigned(addr_latch'length-1 downto 0) := x"B0000000";

    -- Line buffer  signals
    signal s_lb_data_a : STD_ULOGIC_VECTOR(31 downto 0);
    signal s_lb_data_b : STD_ULOGIC_VECTOR(31 downto 0);
    signal s_lb_addr_a : STD_ULOGIC_VECTOR(11 downto 0);
    signal s_lb_addr_b : STD_ULOGIC_VECTOR(11 downto 0);
    signal s_lb_clk_a : STD_ULOGIC;
    signal s_lb_clk_b : STD_ULOGIC;
    signal s_lb_ce_a : STD_ULOGIC;
    signal s_lb_ce_b : STD_ULOGIC;

    -- Stuff exclusive to port a
    signal s_lb_wre_a : STD_ULOGIC;
    signal s_lb_oce_a : STD_ULOGIC;
    signal s_lb_rst_a : STD_ULOGIC;
begin

    -- ACK reception logic
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            qi_WB_SDRAM_ACK <= i_WB_SDRAM_ACK;
            if qi_WB_SDRAM_ACK = '0' and i_WB_SDRAM_ACK='1' then
                SDRAM_ACK_RECEIVED <= '1';

                -- Logic for receiving data from the SDRAM (CPU side)
                if cpu_rw_op_req = '1' and we_latch='0' then -- this should be dalayed or somehting!
                    o_WB_CPU_DAT <= i_WB_SDRAM_DAT;
                end if;
            else
                SDRAM_ACK_RECEIVED <= '0';
            end if;
        end if;
    end process;

    -- This is the condition that makes sure that the address is 
    -- within the appropriate range
    valid_ram_address <= '1' when unsigned(i_WB_CPU_ADDR) >= unsigned(i_WB_CPU_ADDR) and unsigned(i_WB_CPU_ADDR) < unsigned(base_addresses)+sdram_dc_size_c
                             else '0';

    -- Wishbone CPU-SDRAM access logic
    process(i_clk)
    begin
        if rising_edge(i_clk) then
         -- Latch incoming data whenever the CPU is sending something
            if valid_ram_address = '1' and
                i_WB_CPU_CYC='1' and i_WB_CPU_STB='1' 
            then
                cpu_rw_op_req_next <= '1';
                we_next           <= i_WB_CPU_WE;
                ds_next           <= i_WB_CPU_SEL; 
                addr_next         <= i_WB_CPU_ADDR;
                din_latch         <= i_WB_CPU_DAT;
            end if;

        -- Loop to be constantly sipping data from the SDRAM controller
            o_WB_SDRAM_STB  <= '0';
            o_WB_CPU_ACK    <= '0';

            case r_WB_TRANSMISION is
                when IDLE =>
                    we_latch   <= we_next;
                    ds_latch   <= ds_next;
                    addr_latch <= addr_next;

                    if cpu_rw_op_req = '0' then
                        we_latch   <= '0';
                        ds_latch   <= (others => '0');
                        addr_latch <= std_ulogic_vector(dummy_cnt);

                        -- TODO: get rid of this test logic
                        if dummy_cnt >= x"B0000020" then
                            dummy_cnt <= x"B0000000";
                        else
                            dummy_cnt <= dummy_cnt + 4;
                        end if;
                    end if;

                    r_WB_TRANSMISION <= RW_DATA;

                when RW_DATA =>
                    if we_latch = '0' then
                        o_WB_SDRAM_WE   <= '0';
                    else
                        o_WB_SDRAM_WE   <= '1';
                        if cpu_rw_op_req = '1' then
                            o_WB_SDRAM_DAT  <= din_latch; -- I think I can get this out
                        end if;
                    end if;

                    o_WB_SDRAM_STB   <= '1';
                    o_WB_SDRAM_CYC   <= '1';
                    o_WB_SDRAM_ADDR  <= addr_latch;
                    o_WB_SDRAM_SEL   <= ds_latch;
                    r_WB_TRANSMISION <= WAITING_ACK;

                when WAITING_ACK =>
                    if SDRAM_ACK_RECEIVED = '1' then
                        -- Logic if the request came from the CPU

                        if cpu_rw_op_req = '1' then
                            o_WB_CPU_ACK <= '1';
                        end if;

                        r_WB_TRANSMISION <= FINISH_TRASACTION;
                    end if;

                when FINISH_TRASACTION =>
                    -- Logic if the request came internally
                    o_WB_SDRAM_WE       <= '0';
                    o_WB_SDRAM_CYC      <= '0';
                    cpu_rw_op_req       <= cpu_rw_op_req_next;
                    cpu_rw_op_req_next  <= '0';
                    r_WB_TRANSMISION    <= IDLE;

                when others =>
            end case;
        end if;
    end process;


    -- Line buffer memory --------------------------------------------------
    -- -------------------------------------------------------------------------------------------
    DUT_BRAM : entity work.DUALPORT_BRAM
    port map(
        --o_data =>,
        i_data_a =>s_lb_data_a,
        i_data_b =>s_lb_data_b,
        i_addr_a =>s_lb_addr_a,
        i_addr_b =>s_lb_addr_b,
        i_clk_a =>s_lb_clk_a,
        i_clk_b =>s_lb_clk_b,
        i_ce_a =>s_lb_ce_a,
        i_ce_b =>s_lb_ce_b,

        -- Stuff exclusive to port a
        i_wre_a =>s_lb_wre_a,
        i_oce_a =>s_lb_oce_a,
        i_rst_a =>s_lb_rst_a
    );

    -- Wishbone DISPLAY SDRAM access logic
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            if i_WB_CPU_STB = '1' and i_WB_CPU_WE = '1' then
                s_lb_data_a <= i_WB_CPU_DAT;
                s_lb_wre_a  <= '1';
                s_lb_addr_a <= i_WB_CPU_ADDR(s_lb_addr_a'length-1 downto 0);
                -- Somehow wait a clock cycle before setting s_lb_wre_a back to 0
            end if;

        -- Well, the logic here should be that whenever I'm in the
        -- finishing transaction and the cpu_rw_op_req=='0' then I
        -- should take the read data from the SDRAM and put it in the
        -- line buffer.
        end if;
    end process;

    -- NOTE: In the future I can add some simple logic to draw triangles and perform
    -- some elementary manipulations here!
end behavior;
