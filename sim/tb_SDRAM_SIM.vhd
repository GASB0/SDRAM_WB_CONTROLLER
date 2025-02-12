library ieee;
library work;

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library gw5a_sim_models;
library fmf;

entity tb_SDRAM_SIM is
end tb_SDRAM_SIM;

architecture behavior of tb_SDRAM_SIM is
  -- Clock related signals
  signal r_PLL_LOCK, c_100MHZ_CLK, c_100MHZ_45_DEG_CLK, i_CONTROLLER_CLK : std_logic := '0';

  -- Wishbone signals for testing
  signal s_WB_CPU_ACK  , s_WB_GC_ACK   : std_ulogic                     := '0';
  signal s_WB_CPU_CLK  , s_WB_GC_CLK   : std_ulogic                     := '0';
  signal s_WB_CPU_ADDR , s_WB_GC_ADDR  : std_ulogic_vector(31 downto 0) := (others => '0');
  signal s_WB_CPU_DAT_i, s_WB_GC_DAT_i : std_ulogic_vector(31 downto 0) := (others => '0');
  signal s_WB_CPU_DAT_o, s_WB_GC_DAT_o : std_ulogic_vector(31 downto 0) := (others => '0');
  signal s_WB_CPU_RTY  , s_WB_GC_RTY   : std_ulogic;
  signal s_WB_CPU_SEL  , s_WB_GC_SEL   : std_ulogic_vector(3 downto 0)  := (others => '0');
  signal s_WB_CPU_STB  , s_WB_GC_STB   : std_ulogic                     := '0';
  signal s_WB_CPU_WE   , s_WB_GC_WE    : std_ulogic                     := '0';
  signal s_WB_CPU_CYC  , s_WB_GC_CYC   : std_ulogic                     := '0';

  -- SDRAM Side interface
  signal o_SDRAM_ADDR : std_logic_vector(12 downto 0);
  signal o_SDRAM_BS   : std_logic_vector(1 downto 0) := "00";
  signal io_SDRAM_DQ  : std_logic_vector(15 downto 0);
  signal o_SDRAM_RASn : std_logic;
  signal o_SDRAM_CASn : std_logic;
  signal o_SDRAM_WEn  : std_logic;
  signal o_SDRAM_CSn  : std_logic;
  signal o_SDRAM_DQM  : std_logic_vector(1 downto 0);
  signal i_SDRAM_CLK  : std_logic;
  signal o_SDRAM_CKE  : std_logic;

  -- Debug signals
  signal s_SDRAM_READY : std_logic;

  -- Test data
  signal init_cnt     : unsigned(31 downto 0) := (others => '0');

  constant CLK_PERIOD : time := 10 ns;
  constant DELAY_TIME : time := CLK_PERIOD/8;
  signal reset, delayed_clk : std_logic := '0';

begin
  
  MAIN_CLK_GEN : process
  begin
    while true loop
        i_CONTROLLER_CLK <= '0';
        wait for CLK_PERIOD/2;
        i_CONTROLLER_CLK <= '1';
        wait for CLK_PERIOD/2;
    end loop;
  end process MAIN_CLK_GEN;

  DELAYED_CLOCK: process(i_CONTROLLER_CLK, reset)
  begin
      if reset = '1' then
          delayed_clk <= '0'; -- Reset the delayed clock
      else
          delayed_clk <= not delayed_clk after DELAY_TIME; -- Toggle with delay
      end if;
  end process;

  r_PLL_LOCK <= '1' after 10 us;
  c_100MHZ_45_DEG_CLK <= delayed_clk and r_PLL_LOCK;
  c_100MHZ_CLK        <= i_CONTROLLER_CLK and r_PLL_LOCK;

    CONTROLLER_INTERFACE : entity work.SDRAM_CONTROLLER
    port map(
        o_SDRAM_READY => s_SDRAM_READY,

        -- SDRAM Side interface
        o_ADDR      => o_SDRAM_ADDR,
        o_BS        => o_SDRAM_BS,
        io_DQ       => io_SDRAM_DQ,
        o_RASn      => o_SDRAM_RASn,
        o_CASn      => o_SDRAM_CASn,
        o_WEn       => o_SDRAM_WEn,
        o_CSn       => o_SDRAM_CSn,
        o_SDRAM_DQM => o_SDRAM_DQM,
        i_CLK       => c_100MHZ_CLK,
        o_CKE       => i_SDRAM_CLK,
        resetn      => o_SDRAM_CKE,

        -- Graphics controller access
        o_WB_GC_ACK  => s_WB_GC_ACK,
        i_WB_GC_CLK  => s_WB_GC_CLK,
        i_WB_GC_ADDR => s_WB_GC_ADDR,
        i_WB_GC_DAT  => s_WB_GC_DAT_i,
        o_WB_GC_DAT  => s_WB_GC_DAT_o,
        o_WB_GC_RTY  => s_WB_GC_RTY,
        i_WB_GC_SEL  => s_WB_GC_SEL,
        i_WB_GC_STB  => s_WB_GC_STB,
        i_WB_GC_WE   => s_WB_GC_WE,
        i_WB_GC_CYC  => s_WB_GC_CYC,

        -- CPU controller access
        o_WB_CPU_ACK  => s_WB_CPU_ACK,
        i_WB_CPU_CLK  => s_WB_CPU_CLK,
        i_WB_CPU_ADDR => s_WB_CPU_ADDR,
        i_WB_CPU_DAT  => s_WB_CPU_DAT_i,
        o_WB_CPU_DAT  => s_WB_CPU_DAT_o,
        o_WB_CPU_RTY  => s_WB_CPU_RTY,
        i_WB_CPU_SEL  => s_WB_CPU_SEL,
        i_WB_CPU_STB  => s_WB_CPU_STB,
        i_WB_CPU_WE   => s_WB_CPU_WE,
        i_WB_CPU_CYC  => s_WB_CPU_CYC
      );

  -- Now we need some logic for handling wishbone port...
  WB_TEST : process(c_100MHZ_CLK)
      variable v_clk_cnt : INTEGER := 0;
  begin
    if rising_edge(c_100MHZ_CLK) and r_PLL_LOCK= '1' and s_SDRAM_READY='1' then
        if s_WB_CPU_ACK = '1' then
            s_WB_CPU_CYC  <= '0';
        end if;

        if s_WB_GC_ACK = '1' then
            s_WB_GC_CYC   <= '0';
        end if;

        case v_clk_cnt is
            when 0 =>
            when 1 =>
                -- Setting read operation on the CPU port
                s_WB_CPU_ADDR <= (10 =>'1', others => '0');
                s_WB_CPU_WE   <= '0';
                s_WB_CPU_STB  <= '1';
                s_WB_CPU_CYC  <= '1';
                s_WB_CPU_SEL  <= (others => '1');

                -- Setting write operation on the GC port
                s_WB_GC_ADDR <= (others => '0');
                s_WB_GC_WE   <= '1';
                s_WB_GC_STB  <= '1';
                s_WB_GC_CYC  <= '1';
                s_WB_GC_SEL  <= (others => '1');
            when 2 =>
                s_WB_CPU_STB <= '0';
                s_WB_GC_STB  <= '0';
            when others =>
        end case;

        if s_SDRAM_READY='1' then
            v_clk_cnt := v_clk_cnt + 1;
        end if;

    end if;
  end process WB_TEST;

end behavior;
