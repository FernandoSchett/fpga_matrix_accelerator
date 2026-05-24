library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_accelerator_status_leds is
end entity tb_accelerator_status_leds;

architecture sim of tb_accelerator_status_leds is

    constant CLK_PERIOD : time := 10 ns;

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal start : std_logic := '0';
    signal busy : std_logic := '0';
    signal done : std_logic := '0';
    signal load_active : std_logic := '0';
    signal compute_active : std_logic := '0';
    signal store_active : std_logic := '0';
    signal tile_done : std_logic := '0';
    signal error : std_logic := '0';
    signal tiles_processed : unsigned(31 downto 0) := (others => '0');
    signal leds : std_logic_vector(9 downto 0);

    procedure wait_cycles(constant count : natural) is
    begin
        for cycle_idx in 1 to count loop
            wait until rising_edge(clk);
        end loop;
    end procedure;

    procedure wait_led_high(
        signal leds_sig : in std_logic_vector(9 downto 0);
        constant led_idx : natural;
        constant max_cycles : natural;
        constant label_text : string
    ) is
    begin
        for cycle_idx in 0 to max_cycles loop
            wait until rising_edge(clk);
            wait for 1 ns;

            if leds_sig(led_idx) = '1' then
                return;
            end if;
        end loop;

        assert false
            report label_text & ": LED nao ficou alto dentro da janela esperada."
            severity failure;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.accelerator_status_leds
        generic map (
            CLK_FREQ_HZ               => 100,
            HEARTBEAT_HZ              => 5,
            ACTIVITY_BLINK_HZ         => 10,
            PULSE_STRETCH_CYCLES      => 12,
            USE_EXTERNAL_TILE_COUNTER => false
        )
        port map (
            clk             => clk,
            rst             => rst,
            start           => start,
            busy            => busy,
            done            => done,
            load_active     => load_active,
            compute_active  => compute_active,
            store_active    => store_active,
            tile_done       => tile_done,
            error           => error,
            tiles_processed => tiles_processed,
            leds            => leds
        );

    stim_proc : process
        variable heartbeat_before : std_logic;
    begin
        rst <= '1';
        wait_cycles(3);
        rst <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;

        heartbeat_before := leds(0);
        wait_cycles(15);
        wait for 1 ns;

        assert leds(0) /= heartbeat_before
            report "Heartbeat nao alternou."
            severity failure;

        busy <= '1';
        wait_led_high(leds, 1, 20, "busy");
        busy <= '0';
        wait_cycles(2);

        load_active <= '1';
        wait until rising_edge(clk);
        load_active <= '0';
        wait_led_high(leds, 3, 20, "load_active/memory_active");

        compute_active <= '1';
        wait until rising_edge(clk);
        compute_active <= '0';
        wait_led_high(leds, 2, 20, "compute_active");

        store_active <= '1';
        wait until rising_edge(clk);
        store_active <= '0';
        wait_led_high(leds, 3, 20, "store_active/memory_active");

        for tile_idx in 1 to 5 loop
            tile_done <= '1';
            wait until rising_edge(clk);
            tile_done <= '0';
            wait until rising_edge(clk);
            wait for 1 ns;

            assert unsigned(leds(7 downto 4)) = to_unsigned(tile_idx, 4)
                report "Progresso LEDR7 downto LEDR4 nao incrementou com tile_done."
                severity failure;
        end loop;

        done <= '1';
        wait until rising_edge(clk);
        done <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;

        assert leds(8) = '1'
            report "done_latched nao acendeu."
            severity failure;

        wait_cycles(5);
        wait for 1 ns;

        assert leds(8) = '1'
            report "done_latched nao permaneceu aceso."
            severity failure;

        start <= '1';
        wait until rising_edge(clk);
        start <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;

        assert leds(8) = '0'
            report "done_latched nao limpou no proximo start."
            severity failure;

        error <= '1';
        wait until rising_edge(clk);
        error <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;

        assert leds(9) = '1'
            report "error_latched nao acendeu."
            severity failure;

        rst <= '1';
        wait until rising_edge(clk);
        rst <= '0';
        wait until rising_edge(clk);
        wait for 1 ns;

        assert leds(8) = '0' and leds(9) = '0'
            report "Latches de done/error nao limparam no reset."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
