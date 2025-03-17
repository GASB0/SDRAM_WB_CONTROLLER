-- NOTE: This is an implementation of the dualport block ram exemplified in the 
-- Gowin synthesis User manual. This is the example 4 from the page 22
-- /home/gabriel/Software/Gowin_V1.9.10.01_linux/IDE/doc/EN/SUG550-1.8E_GowinSynthesis User Guide.pdf

library IEEE;
library work;

use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

library neorv32;
use neorv32.neorv32_package.all;

entity DUALPORT_BRAM is 
    -- NOTE: Only the port a can be read from!
    port(
        -- Data output
        o_data              : out STD_ULOGIC_VECTOR(31 downto 0); -- This goes to the DC

        -- common port signals
        i_data_a, i_data_b  : in STD_ULOGIC_VECTOR(31 downto 0); -- This comes from the CPU
        i_addr_a, i_addr_b  : in STD_ULOGIC_VECTOR(11 downto 0); -- This comes from the CPU
        i_clk_a, i_clk_b    : in STD_ULOGIC;
        i_ce_a, i_ce_b      : in STD_ULOGIC;

        -- Stuff exclusive to port a
        i_wre_a, i_oce_a, i_rst_a : in STD_ULOGIC
    );
end DUALPORT_BRAM;

architecture behavior of dualport_bram is
    signal MEMORY : mem32_t(0 to (2**(i_addr_b'length) - 1)) := (others => (others => '0'));
    signal data_out_reg_a : STD_ULOGIC_VECTOR(31 downto 0);
begin
    -- Handling the reading operations from the DC side
    process(i_clk_a)
    begin
        if rising_edge(i_clk_a) then
            if i_ce_b='1' then
                MEMORY(TO_INTEGER(UNSIGNED(i_addr_b))) <= i_data_b;
            end if;

            if i_rst_a='1' then
                o_data         <= (others => '0');
                data_out_reg_a <= (others => '0');     
            else
                data_out_reg_a <= MEMORY(TO_INTEGER(UNSIGNED(i_addr_a)));
                if i_oce_a = '1' then
                    o_data <= data_out_reg_a;
                end if;
            end if;

            if i_ce_a='1' and i_wre_a='1' then
                MEMORY(TO_INTEGER(UNSIGNED(i_addr_a))) <= i_data_a;
            end if;
        end if;
    end process;
end behavior;
