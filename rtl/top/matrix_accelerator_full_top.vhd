library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_accel_config_pkg.all;
use work.matrix_tiled_pkg.all;

entity matrix_accelerator_full_top is
    generic (
        N             : positive := DEFAULT_N;
        TILE_SIZE     : positive := DEFAULT_TILE_SIZE;
        NUM_MACS      : positive := DEFAULT_NUM_MACS;
        DATA_WIDTH    : positive := DEFAULT_DATA_WIDTH;
        ACC_WIDTH     : positive := DEFAULT_ACC_WIDTH;
        CLKS_PER_BIT  : positive := 434;
        CLK_FREQ_HZ   : positive := 50000000
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        uart_rx_i : in std_logic;
        uart_tx_o : out std_logic;

        start_button : in std_logic;
        busy_led     : out std_logic;
        done_led     : out std_logic;
        LEDR         : out std_logic_vector(9 downto 0)
    );
end entity matrix_accelerator_full_top;

architecture rtl of matrix_accelerator_full_top is

    constant ADDR_WIDTH      : positive := clog2(N * N);
    constant HOST_DATA_WIDTH : positive := DEFAULT_HOST_DATA_WIDTH;

    signal rx_valid : std_logic;
    signal rx_byte  : std_logic_vector(7 downto 0);

    signal tx_start : std_logic;
    signal tx_byte  : std_logic_vector(7 downto 0);
    signal tx_busy  : std_logic;

    signal cmd_start   : std_logic;
    signal accel_start : std_logic;
    signal accel_busy  : std_logic;
    signal accel_done  : std_logic;
    signal done_seen   : std_logic := '0';

    signal host_wr_en      : std_logic;
    signal host_matrix_sel : std_logic_vector(1 downto 0);
    signal host_addr       : unsigned(ADDR_WIDTH-1 downto 0);
    signal host_data_in    : std_logic_vector(HOST_DATA_WIDTH-1 downto 0);
    signal host_rd_en      : std_logic;
    signal host_rd_addr    : unsigned(ADDR_WIDTH-1 downto 0);
    signal host_data_out   : std_logic_vector(HOST_DATA_WIDTH-1 downto 0);

    signal accel_data_out : signed(ACC_WIDTH-1 downto 0);

    signal perf_total_cycles        : unsigned(63 downto 0);
    signal perf_load_cycles         : unsigned(63 downto 0);
    signal perf_compute_cycles      : unsigned(63 downto 0);
    signal perf_store_cycles        : unsigned(63 downto 0);
    signal perf_num_tiles_processed : unsigned(63 downto 0);
    signal perf_num_mac_ops_issued  : unsigned(63 downto 0);
    signal mac_ops_issued           : unsigned(63 downto 0);

    signal status_load_active    : std_logic;
    signal status_compute_active : std_logic;
    signal status_store_active   : std_logic;
    signal status_tile_done      : std_logic;

begin

    assert N mod TILE_SIZE = 0
        report "matrix_accelerator_full_top exige N multiplo de TILE_SIZE."
        severity failure;

    busy_led <= accel_busy;
    done_led <= done_seen;

    accel_start <= start_button or cmd_start;

    -- O core atual usa RAM interna inferida. Como nao ha RAM externa, as fases
    -- visiveis ficam concentradas em compute/busy.
    status_load_active    <= '0';
    status_compute_active <= accel_busy;
    status_store_active   <= '0';
    status_tile_done      <= accel_done;
    mac_ops_issued        <= to_unsigned(NUM_MACS, mac_ops_issued'length) when accel_busy = '1' else (others => '0');

    host_data_out <= std_logic_vector(resize(accel_data_out, HOST_DATA_WIDTH));

    u_uart_rx : entity work.uart_rx
        generic map (
            CLKS_PER_BIT => CLKS_PER_BIT
        )
        port map (
            clk       => clk,
            rst       => rst,
            rx_serial => uart_rx_i,
            rx_valid  => rx_valid,
            rx_byte   => rx_byte
        );

    u_uart_tx : entity work.uart_tx
        generic map (
            CLKS_PER_BIT => CLKS_PER_BIT
        )
        port map (
            clk       => clk,
            rst       => rst,
            tx_start  => tx_start,
            tx_byte   => tx_byte,
            tx_serial => uart_tx_o,
            tx_busy   => tx_busy
        );

    u_command : entity work.command_interface
        generic map (
            ADDR_WIDTH        => ADDR_WIDTH,
            DATA_WIDTH        => HOST_DATA_WIDTH,
            COUNTER_WIDTH     => 64,
            HOST_READ_LATENCY => 2
        )
        port map (
            clk                      => clk,
            rst                      => rst,
            rx_valid                 => rx_valid,
            rx_byte                  => rx_byte,
            tx_busy                  => tx_busy,
            tx_start                 => tx_start,
            tx_byte                  => tx_byte,
            accelerator_busy         => accel_busy,
            accelerator_done         => done_seen,
            host_wr_en               => host_wr_en,
            host_matrix_sel          => host_matrix_sel,
            host_addr                => host_addr,
            host_data_in             => host_data_in,
            host_rd_en               => host_rd_en,
            host_rd_addr             => host_rd_addr,
            host_data_out            => host_data_out,
            start                    => cmd_start,
            perf_total_cycles        => perf_total_cycles,
            perf_load_cycles         => perf_load_cycles,
            perf_compute_cycles      => perf_compute_cycles,
            perf_store_cycles        => perf_store_cycles,
            perf_num_tiles_processed => perf_num_tiles_processed,
            perf_num_mac_ops_issued  => perf_num_mac_ops_issued
        );

    u_core : entity work.matrix_mult_tiled_top
        generic map (
            N          => N,
            TILE_SIZE  => TILE_SIZE,
            NUM_MACS   => NUM_MACS,
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH
        )
        port map (
            clk         => clk,
            rst         => rst,
            wr_en       => host_wr_en,
            matrix_sel  => host_matrix_sel(0),
            wr_addr     => host_addr,
            data_in     => signed(host_data_in(DATA_WIDTH-1 downto 0)),
            start       => accel_start,
            busy        => accel_busy,
            done        => accel_done,
            result_addr => host_rd_addr,
            data_out    => accel_data_out
        );

    u_perf : entity work.perf_counters
        generic map (
            COUNTER_WIDTH => 64
        )
        port map (
            clk                   => clk,
            rst                   => rst,
            start_count           => accel_start,
            stop_count            => accel_done,
            load_active           => status_load_active,
            compute_active        => status_compute_active,
            store_active          => status_store_active,
            tile_done             => status_tile_done,
            mac_ops_issued        => mac_ops_issued,
            total_cycles          => perf_total_cycles,
            load_cycles           => perf_load_cycles,
            compute_cycles        => perf_compute_cycles,
            store_cycles          => perf_store_cycles,
            num_tiles_processed   => perf_num_tiles_processed,
            num_mac_ops_issued    => perf_num_mac_ops_issued
        );

    u_status_leds : entity work.accelerator_status_leds
        generic map (
            CLK_FREQ_HZ               => CLK_FREQ_HZ,
            HEARTBEAT_HZ              => 1,
            ACTIVITY_BLINK_HZ         => 4,
            PULSE_STRETCH_CYCLES      => CLK_FREQ_HZ / 4,
            USE_EXTERNAL_TILE_COUNTER => true
        )
        port map (
            clk             => clk,
            rst             => rst,
            start           => accel_start,
            busy            => accel_busy,
            done            => accel_done,
            load_active     => status_load_active,
            compute_active  => status_compute_active,
            store_active    => status_store_active,
            tile_done       => status_tile_done,
            error           => '0',
            tiles_processed => perf_num_tiles_processed(31 downto 0),
            leds            => LEDR
        );

    process(clk, rst)
    begin
        if rst = '1' then
            done_seen <= '0';
        elsif rising_edge(clk) then
            if accel_start = '1' then
                done_seen <= '0';
            elsif accel_done = '1' then
                done_seen <= '1';
            end if;
        end if;
    end process;

end architecture rtl;
