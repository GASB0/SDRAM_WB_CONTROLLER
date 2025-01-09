library ieee;
library work;
LIBRARY FMF; 

use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.all;

entity tb_SDRAM_SIM is
end tb_SDRAM_SIM;

architecture behavior of tb_SDRAM_SIM is
  -- SDRAM simulation model
  component mt48lc4m16
    port (
      BA0    : in    std_logic := 'U';
      BA1    : in    std_logic := 'U';
      DQML   : in    std_logic := 'U';
      DQMH   : in    std_logic := 'U';
      DQ0    : inout std_logic := 'U';
      DQ1    : inout std_logic := 'U';
      DQ2    : inout std_logic := 'U';
      DQ3    : inout std_logic := 'U';
      DQ4    : inout std_logic := 'U';
      DQ5    : inout std_logic := 'U';
      DQ6    : inout std_logic := 'U';
      DQ7    : inout std_logic := 'U';
      DQ8    : inout std_logic := 'U';
      DQ9    : inout std_logic := 'U';
      DQ10   : inout std_logic := 'U';
      DQ11   : inout std_logic := 'U';
      DQ12   : inout std_logic := 'U';
      DQ13   : inout std_logic := 'U';
      DQ14   : inout std_logic := 'U';
      DQ15   : inout std_logic := 'U';
      CLK    : in    std_logic := 'U';
      CKE    : in    std_logic := 'U';
      A0     : in    std_logic := 'U';
      A1     : in    std_logic := 'U';
      A2     : in    std_logic := 'U';
      A3     : in    std_logic := 'U';
      A4     : in    std_logic := 'U';
      A5     : in    std_logic := 'U';
      A6     : in    std_logic := 'U';
      A7     : in    std_logic := 'U';
      A8     : in    std_logic := 'U';
      A9     : in    std_logic := 'U';
      A10    : in    std_logic := 'U';
      A11    : in    std_logic := 'U';
      WENeg  : in    std_logic := 'U';
      RASNeg : in    std_logic := 'U';
      CSNeg  : in    std_logic := 'U';
      CASNeg : in    std_logic := 'U'
      );
  end component;

  -- SDRAM controller component
  component SDRAM_CONTROLLER
    port(
      -- SDRAM Side interface
      o_ADDR      : out   std_logic_vector(12 downto 0);
      o_BS        : out   std_logic_vector(1 downto 0) := "00";
      io_DQ       : inout std_logic_vector(15 downto 0);
      o_RASn      : out   std_logic;
      o_CASn      : out   std_logic;
      o_WEn       : out   std_logic;
      o_CSn       : out   std_logic;
      o_SDRAM_DQM : inout std_logic_vector(1 downto 0);
      i_CLK       : in    std_logic;
      o_CKE       : out   std_logic;
      resetn      : in    std_logic := '1';

      -- CPU access (WISHBONE SLAVE interface)
      o_WB_ACK  : out std_ulogic;
      i_WB_CLK  : in  std_ulogic;
      i_WB_ADDR : in  std_ulogic_vector(31 downto 0);
      i_WB_DAT  : in  std_ulogic_vector(31 downto 0);
      o_WB_DAT  : out std_ulogic_vector(31 downto 0) := (others => '0');
      i_WB_RST  : in  std_ulogic;
      i_WB_SEL  : in  std_ulogic_vector(3 downto 0);
      i_WB_STB  : in  std_ulogic;
      i_WB_WE   : in  std_ulogic;
      i_WB_CYC  : in  std_ulogic
      );
  end component;

  component Gowin_PLL
    port (
      lock    : out std_logic;
      clkout0 : out std_logic;
      clkout1 : out std_logic;
      clkin   : in  std_logic
      );
  end component;

  component Gowin_CLKDIV
    port (
      clkout : out std_logic;
      hclkin : in  std_logic;
      resetn : in  std_logic
      );
  end component;

  -- Clock related signals
  signal r_PLL_LOCK, c_100MHZ_CLK, c_100MHZ_45_DEG_CLK, c_25MHZ_CLK, i_CONTROLLER_CLK : std_logic := '0';

  -- Wishbone signals for testing
  signal s_WB_ACK   : std_ulogic                     := '0';
  signal s_WB_CLK   : std_ulogic                     := '0';
  signal s_WB_ADDR  : std_ulogic_vector(31 downto 0) := (others => '0');
  signal s_WB_DAT_i : std_ulogic_vector(31 downto 0) := (others => '0');
  signal s_WB_DAT_o : std_ulogic_vector(31 downto 0) := (others => '0');
  signal s_WB_RST   : std_ulogic                     := '0';
  signal s_WB_SEL   : std_ulogic_vector(3 downto 0)  := (others => '0');
  signal s_WB_STB   : std_ulogic                     := '0';
  signal s_WB_WE    : std_ulogic                     := '0';
  signal s_WB_CYC   : std_ulogic                     := '0';

  -- Signals that go into the SDRAM module
  signal o_SDRAM_ADDR : std_logic_vector(12 downto 0);
  signal o_SDRAM_BS   : std_logic_vector(1 downto 0) := "00";
  signal io_SDRAM_DQ  : std_logic_vector(15 downto 0);
  signal o_SDRAM_RASn : std_logic;
  signal o_SDRAM_CASn : std_logic;
  signal o_SDRAM_WEn  : std_logic;
  signal o_SDRAM_CSn  : std_logic;
  signal o_SDRAM_DQM  : std_logic_vector(1 downto 0);
  signal o_SDRAM_CKE  : std_logic;

  -- Test data
  type data_array is array (0 to 19) of std_logic_vector(31 downto 0);
  constant test_data : data_array := (
    x"000000A0", x"000000A1", x"000000A2", x"000000A3", x"000000A4",
    x"000000A5", x"000000A6", x"000000A7", x"000000A8", x"000000A9",
    x"000000AA", x"0000000C", x"0000000D", x"0000000E", x"0000000F",
    x"00000010", x"00000011", x"00000012", x"00000013", x"00000014"
    );

  -- Counters
  signal write_index : unsigned(15 downto 0) := (others => '0');
  signal read_index  : unsigned(15 downto 0) := (others => '0');

  -- State machine
  type state_type is (s_reset, s_write, s_read, s_done, s_write_stb, s_read_stb);
  signal state : state_type := s_write;

  signal delay_passed : std_logic             := '0';
  signal init_cnt     : unsigned(31 downto 0) := (others => '0');

  constant CLK_PERIOD : time := 20 ns;

begin

  --delay_passed <= '1' when init_cnt = 25000;
  -- this short delay is for simulation only
  delay_passed <= '1' after 3 us; -- this is for the PLL to lock
  
  MAIN_CLK_GEN : process
  begin
    while true loop
        i_CONTROLLER_CLK <= '0';
        wait for CLK_PERIOD/2;
        i_CONTROLLER_CLK <= '1';
        wait for CLK_PERIOD/2;
    end loop;
  end process MAIN_CLK_GEN;

  SDRAM_PLL : Gowin_PLL
    port map (
      lock    => r_PLL_LOCK,
      clkout0 => c_100MHZ_CLK,          -- Clock handling the controller logic
      clkout1 => c_100MHZ_45_DEG_CLK,   -- Clock handling the SDRAM chips
      clkin   => i_CONTROLLER_CLK  -- this is the 50 MHz CLK coming from the board
      );

  CLK_DIV2 : Gowin_CLKDIV
    port map (
      clkout => c_25MHZ_CLK,
      hclkin => i_CONTROLLER_CLK,
      resetn => r_PLL_LOCK
      );

  SDRAM_SIM_MODEL : mt48lc4m16
    port map(
      BA0    => o_SDRAM_BS(0),
      BA1    => o_SDRAM_BS(1),
      DQML   => o_SDRAM_DQM(0),
      DQMH   => o_SDRAM_DQM(1),
      DQ0    => io_SDRAM_DQ(0),
      DQ1    => io_SDRAM_DQ(1),
      DQ2    => io_SDRAM_DQ(2),
      DQ3    => io_SDRAM_DQ(3),
      DQ4    => io_SDRAM_DQ(4),
      DQ5    => io_SDRAM_DQ(5),
      DQ6    => io_SDRAM_DQ(6),
      DQ7    => io_SDRAM_DQ(7),
      DQ8    => io_SDRAM_DQ(8),
      DQ9    => io_SDRAM_DQ(9),
      DQ10   => io_SDRAM_DQ(10),
      DQ11   => io_SDRAM_DQ(11),
      DQ12   => io_SDRAM_DQ(12),
      DQ13   => io_SDRAM_DQ(13),
      DQ14   => io_SDRAM_DQ(14),
      DQ15   => io_SDRAM_DQ(15),
      CLK    => c_100MHZ_45_DEG_CLK,
      CKE    => o_SDRAM_CKE,
      A0     => o_SDRAM_ADDR(0),
      A1     => o_SDRAM_ADDR(1),
      A2     => o_SDRAM_ADDR(2),
      A3     => o_SDRAM_ADDR(3),
      A4     => o_SDRAM_ADDR(4),
      A5     => o_SDRAM_ADDR(5),
      A6     => o_SDRAM_ADDR(6),
      A7     => o_SDRAM_ADDR(7),
      A8     => o_SDRAM_ADDR(8),
      A9     => o_SDRAM_ADDR(9),
      A10    => o_SDRAM_ADDR(10),
      A11    => o_SDRAM_ADDR(11),
      WENeg  => o_SDRAM_WEn,
      RASNeg => o_SDRAM_RASn,
      CSNeg  => o_SDRAM_CSn,
      CASNeg => o_SDRAM_CASn
      );

  CONTROLLER_INTERFACE : SDRAM_CONTROLLER
    port map(
      -- SDRAM interface signals
      o_ADDR      => o_SDRAM_ADDR,
      o_BS        => o_SDRAM_BS,
      io_DQ       => io_SDRAM_DQ,
      o_RASn      => o_SDRAM_RASn,
      o_CASn      => o_SDRAM_CASn,
      o_WEn       => o_SDRAM_WEn,
      o_CSn       => o_SDRAM_CSn,
      o_SDRAM_DQM => o_SDRAM_DQM,
      i_CLK       => c_100MHZ_CLK,
      o_CKE       => o_SDRAM_CKE,
      resetn      => r_PLL_LOCK,

      -- WB interface signals
      o_WB_ACK  => s_WB_ACK,
      i_WB_CLK  => s_WB_CLK,
      i_WB_ADDR => s_WB_ADDR,
      i_WB_DAT  => s_WB_DAT_i,
      o_WB_DAT  => s_WB_DAT_o,
      i_WB_RST  => s_WB_RST,
      i_WB_SEL  => s_WB_SEL,
      i_WB_STB  => s_WB_STB,
      i_WB_WE   => s_WB_WE,
      i_WB_CYC  => s_WB_CYC
      );

  -- logic for waiting a bit so the ram actually initializes
  RAM_DELAY : process(c_100MHZ_CLK)
  begin
    if rising_edge(c_100MHZ_CLK) and r_PLL_LOCK = '1' then
      init_cnt <= init_cnt + 1;
    end if;
  end process RAM_DELAY;

  -- Now we need some logic for handling wishbone port...
  WB_TEST : process(c_25MHZ_CLK)
  begin
    if rising_edge(c_25MHZ_CLK) and delay_passed = '1' then
      case state is
        -- Reset state
        when s_reset =>
          s_WB_RST <= '1';
          s_WB_CYC <= '0';
          s_WB_STB <= '0';
          state    <= s_write;

        -- Write state: Prepare data and assert STB
        when s_write =>
          s_WB_RST               <= '0';
          s_WB_ADDR(write_index'length-1 downto 0) <= std_ulogic_vector(write_index);  -- Address
          s_WB_DAT_i             <= std_ulogic_vector(test_data(to_integer(write_index)));  -- Data to write
          s_WB_WE                <= '1';  -- Enable write
          s_WB_CYC               <= '1';
          s_WB_STB               <= '1';  -- Assert STB
          state                  <= s_write_stb;

        -- Wait for ACK during write
        when s_write_stb =>
          if s_WB_ACK = '1' then
            s_WB_STB    <= '0';         -- Deassert STB after ACK
            write_index <= write_index + 1;
            if write_index = 19 then
              state <= s_read;
            else
              state <= s_write;         -- Move to next write
            end if;
          end if;

        -- Read state: Prepare to read and assert STB
        when s_read =>
          s_WB_ADDR(15 downto 0) <= std_ulogic_vector(read_index);  -- Address
          s_WB_WE                <= '0';  -- Disable write
          s_WB_CYC               <= '1';
          s_WB_STB               <= '1';  -- Assert STB
          state                  <= s_read_stb;

        -- Wait for ACK during read
        when s_read_stb =>
          if s_WB_ACK = '1' then
            s_WB_STB   <= '0';          -- Deassert STB after ACK
            read_index <= read_index + 1;
            if read_index = 19 then
              state <= s_done;
            else
              state <= s_read;          -- Move to next read
            end if;
          end if;

        -- Done state
        when s_done =>
          s_WB_CYC <= '0';
          s_WB_STB <= '0';

        when others =>
      end case;
    end if;
  end process WB_TEST;

end behavior;
