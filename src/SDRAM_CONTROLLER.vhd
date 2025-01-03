library IEEE;
library work;

use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;
--use WORK.custom_functions_and_datatypes.ALL;

entity SDRAM_CONTROLLER is
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
end SDRAM_CONTROLLER;

architecture behavior of SDRAM_CONTROLLER is 
    constant RFRSH_CYCLES : unsigned(9 downto 0) := to_unsigned(500, 10);
    constant FREQ : integer := 100_000_000;

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
    type SETUP_STATE is (s_PRECHARGE_ALL, s_AUTO_REFRESH, s_SET_MODE_REG, s_INIT_CONFIG_DONE);

    signal r_SDRAM_STATE : SDRAM_STATE := s_INIT_DELAY;
    signal r_SETUP_STATE : SETUP_STATE := s_PRECHARGE_ALL;

    signal RAM_CMD : std_logic_vector(3 downto 0); -- Command register for RAM
    signal cfg_now : std_logic := '0'; -- 200 us flag signal

    -- Helper signals?
    signal need_refresh : std_logic := '0';
    signal refresh_cnt  : unsigned(9 downto 0) := to_unsigned(501, 10);
    signal busy : std_logic := '0';
    signal rst_done, rst_done_q : std_logic := '0';
    signal rst_cnt  : unsigned(31 downto 0) := (others => '0');
    signal dq_oen : std_logic := '0';
    signal SDRAM_DQM : std_logic_vector(1 downto 0) := "00";

begin

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
            elsif (refresh_cnt >= RFRSH_CYCLES) then
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
                busy <= '1';
                dq_oen <= '1';
                SDRAM_DQM <= "10";
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
                            v_CLK_CNT := (others => '0');
                        end if;

                    when s_SETUP =>
                    -- Issuing initial setup commands
                        case r_SETUP_STATE is
                            when s_PRECHARGE_ALL    =>
                                RAM_CMD <= CMD_PreCharge when v_CLK_CNT = 1;
                                r_SETUP_STATE <= s_AUTO_REFRESH when v_CLK_CNT = 3;
                                v_CLK_CNT := (others => '0') when v_CLK_CNT = 3;
                            when s_AUTO_REFRESH     =>
                                RAM_CMD <= CMD_AutoRefresh when v_CLK_CNT = 1 or v_CLK_CNT = 3;
                                r_SETUP_STATE <= s_SET_MODE_REG when v_CLK_CNT = 5;
                                v_CLK_CNT := (others => '0') when v_CLK_CNT = 5;
                            when s_SET_MODE_REG     =>
                                RAM_CMD <= CMD_SetModeReg when v_CLK_CNT = 1;
                                r_SETUP_STATE <= s_INIT_CONFIG_DONE when v_CLK_CNT = 3;
                                v_CLK_CNT := (others => '0') when v_CLK_CNT = 3;
                            when s_INIT_CONFIG_DONE =>
                                r_SDRAM_STATE <= s_NORMAL;
                                busy <= '0';
                                r_SETUP_STATE <= s_PRECHARGE_ALL;
                            when others =>
                        end case;

                    when s_NORMAL =>

                    -- Refresh logic
                        refresh_cnt <= refresh_cnt + 1;

                        if need_refresh then -- Add more conditions to issue refresh
                            refresh_cnt <= to_unsigned(0, refresh_cnt'length);
                            RAM_CMD <= CMD_AutoRefresh;
                        end if;

                    -- Accessing banks logic
                    when others =>
                end case;
            end if;
            v_CLK_CNT := v_CLK_CNT + 1;
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