library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

library work;
use work.matrix_tiled_pkg.all;

entity tb_tile_scheduler is
end entity tb_tile_scheduler;

architecture sim of tb_tile_scheduler is

    constant CLK_PERIOD : time := 10 ns;

    constant N4          : positive := 4;
    constant TILE4       : positive := 2;
    constant N4_TILES    : positive := N4 / TILE4;
    constant N4_IDX_WIDTH : positive := clog2(N4_TILES + 1);

    constant N8          : positive := 8;
    constant TILE8       : positive := 2;
    constant N8_TILES    : positive := N8 / TILE8;
    constant N8_IDX_WIDTH : positive := clog2(N8_TILES + 1);

    signal clk : std_logic := '0';
    signal rst : std_logic := '0';

    signal start4 : std_logic := '0';
    signal load_done4 : std_logic := '0';
    signal compute_done4 : std_logic := '0';
    signal store_done4 : std_logic := '0';
    signal busy4 : std_logic;
    signal done4 : std_logic;
    signal init_c_tile4 : std_logic;
    signal load_start4 : std_logic;
    signal compute_start4 : std_logic;
    signal store_start4 : std_logic;
    signal tile_i4 : unsigned(N4_IDX_WIDTH-1 downto 0);
    signal tile_j4 : unsigned(N4_IDX_WIDTH-1 downto 0);
    signal tile_k4 : unsigned(N4_IDX_WIDTH-1 downto 0);

    signal start8 : std_logic := '0';
    signal load_done8 : std_logic := '0';
    signal compute_done8 : std_logic := '0';
    signal store_done8 : std_logic := '0';
    signal busy8 : std_logic;
    signal done8 : std_logic;
    signal init_c_tile8 : std_logic;
    signal load_start8 : std_logic;
    signal compute_start8 : std_logic;
    signal store_start8 : std_logic;
    signal tile_i8 : unsigned(N8_IDX_WIDTH-1 downto 0);
    signal tile_j8 : unsigned(N8_IDX_WIDTH-1 downto 0);
    signal tile_k8 : unsigned(N8_IDX_WIDTH-1 downto 0);

    procedure wait_for_pulse(
        signal pulse : in std_logic;
        constant name_text : string
    ) is
    begin
        for cycle_idx in 0 to 2000 loop
            wait until rising_edge(clk);
            wait for 1 ns;

            if pulse = '1' then
                return;
            end if;
        end loop;

        assert false
            report "Timeout aguardando pulso de " & name_text
            severity failure;
    end procedure;

    procedure wait_for_done(
        signal done_signal : in std_logic;
        constant name_text : string
    ) is
    begin
        for cycle_idx in 0 to 5000 loop
            wait until rising_edge(clk);
            wait for 1 ns;

            if done_signal = '1' then
                return;
            end if;
        end loop;

        assert false
            report "Timeout aguardando done de " & name_text
            severity failure;
    end procedure;

    procedure assert_indices(
        signal tile_i_sig : in unsigned;
        signal tile_j_sig : in unsigned;
        signal tile_k_sig : in unsigned;
        constant expected_i : natural;
        constant expected_j : natural;
        constant expected_k : natural;
        constant context_text : string
    ) is
    begin
        assert to_integer(tile_i_sig) = expected_i
            report context_text & ": tile_i incorreto."
            severity failure;

        assert to_integer(tile_j_sig) = expected_j
            report context_text & ": tile_j incorreto."
            severity failure;

        assert to_integer(tile_k_sig) = expected_k
            report context_text & ": tile_k incorreto."
            severity failure;
    end procedure;

begin

    clk <= not clk after CLK_PERIOD / 2;

    dut4 : entity work.tile_scheduler
        generic map (
            N         => N4,
            TILE_SIZE => TILE4
        )
        port map (
            clk           => clk,
            rst           => rst,
            start         => start4,
            load_done     => load_done4,
            compute_done  => compute_done4,
            store_done    => store_done4,
            busy          => busy4,
            done          => done4,
            init_c_tile   => init_c_tile4,
            load_start    => load_start4,
            compute_start => compute_start4,
            store_start   => store_start4,
            tile_i        => tile_i4,
            tile_j        => tile_j4,
            tile_k        => tile_k4
        );

    dut8 : entity work.tile_scheduler
        generic map (
            N         => N8,
            TILE_SIZE => TILE8
        )
        port map (
            clk           => clk,
            rst           => rst,
            start         => start8,
            load_done     => load_done8,
            compute_done  => compute_done8,
            store_done    => store_done8,
            busy          => busy8,
            done          => done8,
            init_c_tile   => init_c_tile8,
            load_start    => load_start8,
            compute_start => compute_start8,
            store_start   => store_start8,
            tile_i        => tile_i8,
            tile_j        => tile_j8,
            tile_k        => tile_k8
        );

    mock_load4 : process
    begin
        load_done4 <= '0';
        wait until rst = '0';

        loop
            wait until rising_edge(clk);
            load_done4 <= '0';

            if load_start4 = '1' then
                wait until rising_edge(clk);
                load_done4 <= '1';
                wait until rising_edge(clk);
                load_done4 <= '0';
            end if;
        end loop;
    end process;

    mock_compute4 : process
    begin
        compute_done4 <= '0';
        wait until rst = '0';

        loop
            wait until rising_edge(clk);
            compute_done4 <= '0';

            if compute_start4 = '1' then
                for delay_cycle in 0 to 1 loop
                    wait until rising_edge(clk);
                end loop;

                compute_done4 <= '1';
                wait until rising_edge(clk);
                compute_done4 <= '0';
            end if;
        end loop;
    end process;

    mock_store4 : process
    begin
        store_done4 <= '0';
        wait until rst = '0';

        loop
            wait until rising_edge(clk);
            store_done4 <= '0';

            if store_start4 = '1' then
                wait until rising_edge(clk);
                store_done4 <= '1';
                wait until rising_edge(clk);
                store_done4 <= '0';
            end if;
        end loop;
    end process;

    mock_load8 : process
    begin
        load_done8 <= '0';
        wait until rst = '0';

        loop
            wait until rising_edge(clk);
            load_done8 <= '0';

            if load_start8 = '1' then
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                load_done8 <= '1';
                wait until rising_edge(clk);
                load_done8 <= '0';
            end if;
        end loop;
    end process;

    mock_compute8 : process
    begin
        compute_done8 <= '0';
        wait until rst = '0';

        loop
            wait until rising_edge(clk);
            compute_done8 <= '0';

            if compute_start8 = '1' then
                for delay_cycle in 0 to 2 loop
                    wait until rising_edge(clk);
                end loop;

                compute_done8 <= '1';
                wait until rising_edge(clk);
                compute_done8 <= '0';
            end if;
        end loop;
    end process;

    mock_store8 : process
    begin
        store_done8 <= '0';
        wait until rst = '0';

        loop
            wait until rising_edge(clk);
            store_done8 <= '0';

            if store_start8 = '1' then
                wait until rising_edge(clk);
                wait until rising_edge(clk);
                store_done8 <= '1';
                wait until rising_edge(clk);
                store_done8 <= '0';
            end if;
        end loop;
    end process;

    stim_proc : process
        variable init_count    : natural := 0;
        variable load_count    : natural := 0;
        variable compute_count : natural := 0;
        variable store_count   : natural := 0;
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait until rising_edge(clk);

        start4 <= '1';
        wait until rising_edge(clk);
        start4 <= '0';
        wait for 1 ns;

        assert busy4 = '1'
            report "Scheduler N=4 nao entrou em busy."
            severity failure;

        init_count := 0;
        load_count := 0;
        compute_count := 0;
        store_count := 0;

        for i_idx in 0 to N4_TILES-1 loop
            for j_idx in 0 to N4_TILES-1 loop
                wait_for_pulse(init_c_tile4, "init_c_tile N=4");
                init_count := init_count + 1;
                assert_indices(tile_i4, tile_j4, tile_k4, i_idx, j_idx, 0, "N=4 init");

                for k_idx in 0 to N4_TILES-1 loop
                    wait_for_pulse(load_start4, "load_start N=4");
                    load_count := load_count + 1;
                    assert_indices(tile_i4, tile_j4, tile_k4, i_idx, j_idx, k_idx, "N=4 load");

                    wait_for_pulse(compute_start4, "compute_start N=4");
                    compute_count := compute_count + 1;
                    assert_indices(tile_i4, tile_j4, tile_k4, i_idx, j_idx, k_idx, "N=4 compute");
                end loop;

                wait_for_pulse(store_start4, "store_start N=4");
                store_count := store_count + 1;

                assert to_integer(tile_i4) = i_idx and to_integer(tile_j4) = j_idx
                    report "N=4 store usou tile_i/tile_j incorretos."
                    severity failure;
            end loop;
        end loop;

        wait_for_done(done4, "N=4");

        assert init_count = N4_TILES * N4_TILES
            report "N=4 gerou quantidade incorreta de init_c_tile."
            severity failure;

        assert load_count = N4_TILES * N4_TILES * N4_TILES
            report "N=4 gerou quantidade incorreta de load_start."
            severity failure;

        assert compute_count = N4_TILES * N4_TILES * N4_TILES
            report "N=4 gerou quantidade incorreta de compute_start."
            severity failure;

        assert store_count = N4_TILES * N4_TILES
            report "N=4 gerou quantidade incorreta de store_start."
            severity failure;

        wait until rising_edge(clk);

        start8 <= '1';
        wait until rising_edge(clk);
        start8 <= '0';
        wait for 1 ns;

        assert busy8 = '1'
            report "Scheduler N=8 nao entrou em busy."
            severity failure;

        init_count := 0;
        load_count := 0;
        compute_count := 0;
        store_count := 0;

        for i_idx in 0 to N8_TILES-1 loop
            for j_idx in 0 to N8_TILES-1 loop
                wait_for_pulse(init_c_tile8, "init_c_tile N=8");
                init_count := init_count + 1;
                assert_indices(tile_i8, tile_j8, tile_k8, i_idx, j_idx, 0, "N=8 init");

                for k_idx in 0 to N8_TILES-1 loop
                    wait_for_pulse(load_start8, "load_start N=8");
                    load_count := load_count + 1;
                    assert_indices(tile_i8, tile_j8, tile_k8, i_idx, j_idx, k_idx, "N=8 load");

                    wait_for_pulse(compute_start8, "compute_start N=8");
                    compute_count := compute_count + 1;
                    assert_indices(tile_i8, tile_j8, tile_k8, i_idx, j_idx, k_idx, "N=8 compute");
                end loop;

                wait_for_pulse(store_start8, "store_start N=8");
                store_count := store_count + 1;

                assert to_integer(tile_i8) = i_idx and to_integer(tile_j8) = j_idx
                    report "N=8 store usou tile_i/tile_j incorretos."
                    severity failure;
            end loop;
        end loop;

        wait_for_done(done8, "N=8");

        assert init_count = N8_TILES * N8_TILES
            report "N=8 gerou quantidade incorreta de init_c_tile."
            severity failure;

        assert load_count = N8_TILES * N8_TILES * N8_TILES
            report "N=8 gerou quantidade incorreta de load_start."
            severity failure;

        assert compute_count = N8_TILES * N8_TILES * N8_TILES
            report "N=8 gerou quantidade incorreta de compute_start."
            severity failure;

        assert store_count = N8_TILES * N8_TILES
            report "N=8 gerou quantidade incorreta de store_start."
            severity failure;

        report "SIM_RESULT: PASS" severity note;
        finish;
    end process;

end architecture sim;
