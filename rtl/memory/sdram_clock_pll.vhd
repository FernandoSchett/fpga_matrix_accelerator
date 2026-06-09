library ieee;
use ieee.std_logic_1164.all;

library altera_mf;
use altera_mf.altera_mf_components.all;

entity sdram_clock_pll is
    generic (
        INPUT_CLK_PERIOD_PS : natural := 20000;
        PHASE_SHIFT_PS      : string := "-3000"
    );
    port (
        clk_in    : in std_logic;
        rst       : in std_logic;
        sdram_clk : out std_logic;
        locked    : out std_logic
    );
end entity sdram_clock_pll;

architecture rtl of sdram_clock_pll is
    signal pll_inclk : std_logic_vector(1 downto 0) := (others => '0');
    signal pll_clk   : std_logic_vector(5 downto 0);
begin
    pll_inclk(0) <= clk_in;
    pll_inclk(1) <= '0';

    sdram_clk <= pll_clk(0);

    u_altpll : altpll
        generic map (
            operation_mode          => "NORMAL",
            intended_device_family  => "Cyclone V",
            inclk0_input_frequency  => INPUT_CLK_PERIOD_PS,
            clk0_multiply_by        => 1,
            clk0_divide_by          => 1,
            clk0_duty_cycle         => 50,
            clk0_phase_shift        => PHASE_SHIFT_PS,
            clk0_counter            => "C0",
            clk1_counter            => "UNUSED",
            clk2_counter            => "UNUSED",
            clk3_counter            => "UNUSED",
            clk4_counter            => "UNUSED",
            clk5_counter            => "UNUSED",
            clk6_counter            => "UNUSED",
            clk7_counter            => "UNUSED",
            clk8_counter            => "UNUSED",
            clk9_counter            => "UNUSED",
            feedback_source         => "CLK0",
            compensate_clock        => "CLK0",
            bandwidth_type          => "AUTO",
            lpm_type                => "altpll",
            port_areset             => "PORT_USED",
            port_inclk0             => "PORT_USED",
            port_locked             => "PORT_USED",
            port_clk0               => "PORT_USED"
        )
        port map (
            areset => rst,
            inclk  => pll_inclk,
            clk    => pll_clk,
            locked => locked
        );
end architecture rtl;
