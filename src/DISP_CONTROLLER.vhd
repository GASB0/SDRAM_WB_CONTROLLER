library IEEE;
library work;

use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

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
    signal cpu_rw_op_req, cpu_rw_op_req_next, we_latch, port_req_latch : std_ulogic := '0';
    signal addr_latch, din_latch    : std_ulogic_vector(31 downto 0) := (others => '0');
    signal ds_latch : std_ulogic_vector(3 downto 0)  := (others => '0'); 

    signal base_addresses    : std_ulogic_vector(31 downto 0) := sdram_dc_base_addr_c;
    signal valid_ram_address : std_ulogic;

begin

    -- ACK reception logic
    process(i_clk)
    begin
        if rising_edge(i_clk) then
            qi_WB_SDRAM_ACK <= i_WB_SDRAM_ACK;
            if qi_WB_SDRAM_ACK = '0' and i_WB_SDRAM_ACK='1' then
                SDRAM_ACK_RECEIVED <= '1';
            else
                SDRAM_ACK_RECEIVED <= '0';
            end if;
        end if;
    end process;

    -- This is the condition that makes sure that the address is 
    -- within the appropriate range
    valid_ram_address <= '1' when unsigned(i_WB_CPU_ADDR) >= unsigned(i_WB_CPU_ADDR) and unsigned(i_WB_CPU_ADDR) < unsigned(base_addresses)+sdram_dc_size_c
                             else '0';

    -- Logic for receiving data from the SDRAM (CPU side)
    process(i_WB_SDRAM_ACK)
    begin
        if rising_edge(i_WB_SDRAM_ACK) then
            if we_latch = '1' then
                -- I think I don't have to do anything here?
            else
                o_WB_CPU_DAT <= i_WB_SDRAM_DAT;
            end if;
        end if;
    end process;

    -- Wishbone CPU-SDRAM access logic
    process(i_clk)
        variable dummy_cnt : unsigned(addr_latch'length-1 downto 0) := (others => '0');
    begin
        if rising_edge(i_clk) then
         -- Latch incoming data whenever the CPU is sending something
            if valid_ram_address = '1' and
                i_WB_CPU_CYC='1' and i_WB_CPU_STB='1' 
            then
                cpu_rw_op_req_next <= '1';
                we_latch           <= i_WB_CPU_WE;
                ds_latch           <= i_WB_CPU_SEL; 
                din_latch          <= i_WB_CPU_DAT;
                addr_latch         <= i_WB_CPU_ADDR;
            end if;

        -- Loop to be constantly sipping data from the SDRAM controller
            o_WB_SDRAM_STB  <= '0';
            o_WB_CPU_ACK    <= '0';

            case r_WB_TRANSMISION is
                when IDLE =>
                    if dummy_cnt >= x"10" then
                        dummy_cnt := (others => '0');
                    else
                        dummy_cnt := dummy_cnt + 1;
                    end if;

                    if cpu_rw_op_req = '0' then
                        we_latch   <= '0';
                        ds_latch   <= (others => '0');
                        addr_latch <= (others => '0');
                    end if;

                    r_WB_TRANSMISION <= RW_DATA;

                when RW_DATA =>
                    if we_latch = '0' then
                        o_WB_SDRAM_WE   <= '0';
                    else
                        o_WB_SDRAM_WE   <= '1';
                        if cpu_rw_op_req = '1' then
                            o_WB_SDRAM_DAT  <= din_latch; -- feeding new data to be written
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
                        o_WB_CPU_ACK     <= '1';
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

    -- Wishbone DISPLAY SDRAM access logic
    process(i_clk)
    begin
        if rising_edge(i_clk) then
        -- TODO: Write logic for writing into BRAM memory
        -- BRAM_DATA_IN <= BRAM_WRITE_BUFFER
        end if;
    end process;
end behavior;
