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
    type CONTROLLER_STATE is     (VRAM_WRITE, VRAM_READ);
    type WB_TRANSMISION_STATE is (WAITING_ACK, IDLE, RW_DATA, SENDING_DATA);

    signal r_WB_TRANSMISION : WB_TRANSMISION_STATE := SENDING_DATA;
    signal SDRAM_ACK_RECEIVED, qi_WB_SDRAM_ACK : std_ulogic;
    signal qi_WB_CPU_CYC : std_ulogic;
    signal BRAM_WRITE_BUFFER : std_ulogic_vector(31 downto 0);
    signal start_rw_op, we_latch, port_req_latch : std_ulogic := '0';
    signal addr_latch, din_latch    : std_ulogic_vector(31 downto 0) := (others => '0');
    signal ds_latch : std_ulogic_vector(3 downto 0)  := (others => '0'); 

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

    -- Latching inputs from the CPU side?
    process(i_WB_CPU_CYC, i_WB_CPU_STB)
    begin
        start_rw_op    <= '0';

        if i_WB_CPU_CYC='1' and i_WB_CPU_STB='1' then
            start_rw_op    <= '1';
        end if;
    end process;

    -- Wishbone tramission logic for the SDRAM side
    process(i_clk)
    begin
        if rising_edge(i_clk) then
        -- Loop to be constantly sipping data from the SDRAM controller
            case r_WB_TRANSMISION is
                when IDLE =>
                    if start_rw_op='1' then
                        r_WB_TRANSMISION <= RW_DATA;
                        we_latch         <= i_WB_CPU_WE; -- I think this is going to fail
                        ds_latch         <= i_WB_CPU_SEL; 
                        din_latch        <= i_WB_CPU_DAT;
                        addr_latch       <= i_WB_CPU_ADDR;
                    end if;
                when RW_DATA =>
                    if we_latch = '0' then
                        o_WB_SDRAM_WE   <= '0';
                    else
                        o_WB_SDRAM_WE   <= '1';
                        o_WB_SDRAM_DAT  <= din_latch; -- feeding new data to be written
                    end if;

                    o_WB_SDRAM_CYC   <= '1';
                    o_WB_SDRAM_ADDR  <= addr_latch;
                    o_WB_SDRAM_SEL   <= ds_latch;
                    r_WB_TRANSMISION <= WAITING_ACK;

                when WAITING_ACK =>
                    o_WB_SDRAM_STB  <= '0';
                    if SDRAM_ACK_RECEIVED = '1' then
                        if we_latch = '1' then
                            -- I think I don't have to do anything here?
                        else
                            BRAM_WRITE_BUFFER <= i_WB_SDRAM_DAT;
                        end if;

                        -- Resetting signals to default idle state
                        o_WB_SDRAM_WE    <= '0';
                        o_WB_SDRAM_CYC   <= '0';
                        r_WB_TRANSMISION <= IDLE;
                    end if;

                when others =>
            end case;
        end if;
    end process;

    -- Logic for storing data into line buffer (BRAM)
    process(i_clk)
    begin
        if rising_edge(i_clk) then
        -- TODO: Write logic for writing into BRAM memory
        -- BRAM_DATA_IN <= BRAM_WRITE_BUFFER
        end if;
    end process;
end behavior;
