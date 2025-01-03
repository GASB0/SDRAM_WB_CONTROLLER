library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_SDRAM_CONTROLLER is
end tb_SDRAM_CONTROLLER;

architecture behavior of tb_SDRAM_CONTROLLER is

    -- Component declaration for the DUT (Device Under Test)
    component SDRAM_CONTROLLER
        port(
            o_ADDR : out std_logic_vector(12 downto 0);
            o_BS   : out std_logic_vector(1 downto 0);
            io_DQ  : inout std_logic_vector(15 downto 0);
            o_RASn : out std_logic;
            o_CASn : out std_logic;
            o_WEn  : out std_logic;
            o_CSn  : out std_logic;
            o_LDQM : out std_logic;
            o_UDQM : out std_logic;
            i_CLK  : in std_logic;
            i_CKE  : out std_logic;
            resetn : in std_logic
        );
    end component;

    -- Signals to connect to the DUT
    signal s_ADDR : std_logic_vector(12 downto 0);
    signal s_BS   : std_logic_vector(1 downto 0);
    signal s_DQ   : std_logic_vector(15 downto 0);
    signal s_RASn : std_logic;
    signal s_CASn : std_logic;
    signal s_WEn  : std_logic;
    signal s_CSn  : std_logic;
    signal s_LDQM : std_logic;
    signal s_UDQM : std_logic;
    signal s_CLK  : std_logic := '0';
    signal s_CKE  : std_logic;
    signal s_resetn : std_logic := '1';

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
            o_LDQM => s_LDQM,
            o_UDQM => s_UDQM,
            i_CLK  => s_CLK,
            i_CKE  => s_CKE,
            resetn => s_resetn
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
    

end behavior;
