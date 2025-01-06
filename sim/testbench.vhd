library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_SDRAM_CONTROLLER is
end tb_SDRAM_CONTROLLER;

architecture behavior of tb_SDRAM_CONTROLLER is
    -- Component declaration for the DUT (Device Under Test)
    component SDRAM_CONTROLLER
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
    end component;

    -- Signals to connect to the DUT
    signal s_ADDR      : std_logic_vector(12 downto 0) := (others => '0');
    signal s_BS        : std_logic_vector(1 downto 0) := (others => '0');
    signal s_DQ        : std_logic_vector(15 downto 0) := (others => '0');
    signal s_RASn      : std_logic := '0';
    signal s_CASn      : std_logic := '0';
    signal s_WEn       : std_logic := '0';
    signal s_CSn       : std_logic := '0';
    signal s_SDRAM_DQM : std_logic_vector(1 downto 0) := (others => '0');
    signal s_CLK       : std_logic := '0';
    signal s_CKE       : std_logic := '0';
    signal s_resetn    : std_logic := '1';

    signal s_WB_ACK  : std_ulogic := '0';
    signal s_WB_CLK  : std_ulogic := '0';
    signal s_WB_ADDR : std_ulogic_vector( 31 downto 0 ) := (others => '0');
    signal s_WB_DAT_i: std_ulogic_vector( 31 downto 0 ) := (others => '0');
    signal s_WB_DAT_o: std_ulogic_vector( 31 downto 0 ) := (others => '0');
    signal s_WB_RST  : std_ulogic := '0';
    signal s_WB_SEL  : std_ulogic_vector( 3 downto 0 ) := (others => '0');
    signal s_WB_STB  : std_ulogic := '0';
    signal s_WB_WE   : std_ulogic := '0';
    signal s_WB_CYC  : std_ulogic := '0';
              
    -- Clock period definition for 100 MHz
    constant CLK_PERIOD : time := 10 ns;

begin

    -- Instantiate the SDRAM_CONTROLLER (DUT)
    uut: SDRAM_CONTROLLER  
        port map(
            o_ADDR => s_ADDR,
            o_BS   => s_BS,
            io_DQ  => s_DQ,
            o_RASn => s_RASn,
            o_CASn => s_CASn,
            o_WEn  => s_WEn,
            o_CSn  => s_CSn,
            SDRAM_DQM => s_SDRAM_DQM,
            i_CLK  => s_CLK,
            i_CKE  => s_CKE,
            resetn => s_resetn,
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


    -- Clock generation process
    clk_gen: process
    begin
        while true loop
            s_CLK <= '1';
            wait for CLK_PERIOD / 2;
            s_CLK <= '0';
            wait for CLK_PERIOD / 2;
        end loop;
    end process clk_gen;
    
    -- Wishbone interface test
    wb_test: process(s_CLK)
      variable clk_cnt : unsigned(31 downto 0) := (others => '0');
    begin
      if rising_edge(s_CLK) then
        if clk_cnt = to_unsigned(25000, clk_cnt'length) then
          s_WB_ADDR <= std_ulogic_vector(to_unsigned(5, s_WB_ADDR'length));
          s_WB_DAT_i <= std_ulogic_vector(to_unsigned(10, s_WB_ADDR'length));
          s_WB_WE <= '0';
          s_WB_SEL <= "0000";
          s_WB_STB <= '1';
          s_WB_CYC <= '1';
        end if;

        s_WB_STB <= '0' when s_WB_ACK ='1';
        s_WB_CYC <= '0' when s_WB_ACK ='1';

        clk_cnt := clk_cnt + 1;
      end if;
    end process wb_test;
end behavior;
