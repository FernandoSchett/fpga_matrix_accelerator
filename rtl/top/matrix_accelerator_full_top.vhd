library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_accel_config_pkg.all;
use work.matrix_tiled_pkg.all;

entity matrix_accelerator_full_top is
    generic (
        N                   : positive := DEFAULT_N;
        TILE_SIZE           : positive := DEFAULT_TILE_SIZE;
        NUM_MACS            : positive := DEFAULT_NUM_MACS;
        DATA_WIDTH          : positive := DEFAULT_DATA_WIDTH;
        ACC_WIDTH           : positive := DEFAULT_ACC_WIDTH;
        MEM_TYPE            : string := "internal_fpga_ram";
        DATAFLOW            : string := "output_stationary";
        BUFFERING_MODE      : string := "single";
        MEMORY_BURST_LEN    : natural := 1;
        MAC_PIPELINE_STAGES : natural := 0;
        MEMORY_BANKS_A      : positive := 1;
        MEMORY_BANKS_B      : positive := 1;
        CLKS_PER_BIT        : positive := 434;
        CLK_FREQ_HZ         : positive := 50000000;
        UART_FIFO_DEPTH     : positive := 64;
        ENABLE_SIGNALTAP    : boolean := true
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        uart_rx_i : in std_logic;
        uart_tx_o : out std_logic;

        start_button : in std_logic;
        LEDR         : out std_logic_vector(9 downto 0);
        HEX0         : out std_logic_vector(6 downto 0);
        HEX1         : out std_logic_vector(6 downto 0);
        HEX2         : out std_logic_vector(6 downto 0);
        HEX3         : out std_logic_vector(6 downto 0);
        HEX4         : out std_logic_vector(6 downto 0);
        HEX5         : out std_logic_vector(6 downto 0)
    );
end entity matrix_accelerator_full_top;

architecture rtl of matrix_accelerator_full_top is

    constant ADDR_WIDTH      : positive := clog2(N * N);
    constant HOST_DATA_WIDTH : positive := DEFAULT_HOST_DATA_WIDTH;

    signal uart_rx_valid : std_logic;
    signal uart_rx_byte  : std_logic_vector(7 downto 0);

    signal cmd_rx_valid : std_logic;
    signal cmd_rx_ready : std_logic;
    signal cmd_rx_byte  : std_logic_vector(7 downto 0);

    signal rx_fifo_rd_en       : std_logic;
    signal rx_fifo_empty       : std_logic;
    signal rx_fifo_full        : std_logic;
    signal rx_fifo_almost_full : std_logic;
    signal rx_fifo_overflow    : std_logic;
    signal rx_fifo_underflow   : std_logic;

    signal cmd_tx_start : std_logic;
    signal cmd_tx_byte  : std_logic_vector(7 downto 0);
    signal cmd_tx_busy  : std_logic;

    signal uart_tx_start : std_logic;
    signal uart_tx_byte  : std_logic_vector(7 downto 0);
    signal uart_tx_busy  : std_logic;

    signal tx_fifo_rd_en       : std_logic;
    signal tx_fifo_rd_data     : std_logic_vector(7 downto 0);
    signal tx_fifo_empty       : std_logic;
    signal tx_fifo_full        : std_logic;
    signal tx_fifo_almost_full : std_logic;
    signal tx_fifo_overflow    : std_logic;
    signal tx_fifo_underflow   : std_logic;

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

    signal accel_data_out   : signed(ACC_WIDTH-1 downto 0);
    signal core_result_addr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');

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

    signal debug_probe_data   : std_logic_vector(127 downto 0) := (others => '0');
    signal debug_trigger_data : std_logic_vector(7 downto 0) := (others => '0');

    attribute keep : boolean;
    attribute preserve : boolean;
    attribute keep of debug_probe_data : signal is true;
    attribute keep of debug_trigger_data : signal is true;
    attribute preserve of debug_probe_data : signal is true;
    attribute preserve of debug_trigger_data : signal is true;

    -- Debug por LED direto no top.
    -- LEDR[0] = heartbeat
    -- LEDR[1] = uart_rx_valid visto
    -- LEDR[2] = cmd_rx_valid visto
    -- LEDR[3] = cmd_tx_start visto
    -- LEDR[4] = host_wr_en visto
    -- LEDR[5] = cmd_start visto
    -- LEDR[6] = accel_busy visto
    -- LEDR[7] = accel_done visto
    -- LEDR[8] = host_rd_en visto
    -- LEDR[9] = erro FIFO ou SW1/start_button ligado
    constant DBG_HEARTBEAT_TOGGLE_CYCLES : positive := CLK_FREQ_HZ / 2;

    signal dbg_heartbeat_count : natural range 0 to DBG_HEARTBEAT_TOGGLE_CYCLES-1 := 0;
    signal dbg_heartbeat_reg   : std_logic := '0';

    signal dbg_uart_rx_seen   : std_logic := '0';
    signal dbg_cmd_rx_seen    : std_logic := '0';
    signal dbg_cmd_tx_seen    : std_logic := '0';
    signal dbg_host_wr_seen   : std_logic := '0';
    signal dbg_cmd_start_seen : std_logic := '0';
    signal dbg_busy_seen      : std_logic := '0';
    signal dbg_done_seen      : std_logic := '0';
    signal dbg_host_rd_seen   : std_logic := '0';
    signal dbg_error_seen     : std_logic := '0';

begin

    assert N mod TILE_SIZE = 0
        report "matrix_accelerator_full_top exige N multiplo de TILE_SIZE."
        severity failure;

    accel_start <= start_button or cmd_start;

    -- O core atual usa RAM interna inferida. Como nao ha RAM externa, as fases
    -- visiveis ficam concentradas em compute/busy.
    status_load_active    <= '0';
    status_compute_active <= accel_busy;
    status_store_active   <= '0';
    status_tile_done      <= accel_done;
    mac_ops_issued        <= to_unsigned(NUM_MACS, mac_ops_issued'length) when accel_busy = '1' else (others => '0');

    host_data_out <= std_logic_vector(resize(accel_data_out, HOST_DATA_WIDTH));

    rx_fifo_rd_en <= cmd_rx_ready and not rx_fifo_empty;
    cmd_rx_valid  <= rx_fifo_rd_en;
    cmd_tx_busy   <= tx_fifo_almost_full or tx_fifo_full;

    tx_fifo_rd_en <= '1' when uart_tx_busy = '0' and tx_fifo_empty = '0' else '0';
    uart_tx_start <= tx_fifo_rd_en;
    uart_tx_byte  <= tx_fifo_rd_data;

    u_uart_rx : entity work.uart_rx
        generic map (
            CLKS_PER_BIT => CLKS_PER_BIT
        )
        port map (
            clk       => clk,
            rst       => rst,
            rx_serial => uart_rx_i,
            rx_valid  => uart_rx_valid,
            rx_byte   => uart_rx_byte
        );

    u_rx_fifo : entity work.uart_byte_fifo
        generic map (
            FIFO_DEPTH        => UART_FIFO_DEPTH,
            ALMOST_FULL_LEVEL => UART_FIFO_DEPTH - 4,
            RAM_BLOCK_TYPE    => "M10K"
        )
        port map (
            clk         => clk,
            rst         => rst,
            wr_en       => uart_rx_valid,
            wr_data     => uart_rx_byte,
            rd_en       => rx_fifo_rd_en,
            rd_data     => cmd_rx_byte,
            empty       => rx_fifo_empty,
            full        => rx_fifo_full,
            almost_full => rx_fifo_almost_full,
            overflow    => rx_fifo_overflow,
            underflow   => rx_fifo_underflow
        );

    u_uart_tx : entity work.uart_tx
        generic map (
            CLKS_PER_BIT => CLKS_PER_BIT
        )
        port map (
            clk       => clk,
            rst       => rst,
            tx_start  => uart_tx_start,
            tx_byte   => uart_tx_byte,
            tx_serial => uart_tx_o,
            tx_busy   => uart_tx_busy
        );

    u_tx_fifo : entity work.uart_byte_fifo
        generic map (
            FIFO_DEPTH        => UART_FIFO_DEPTH,
            ALMOST_FULL_LEVEL => UART_FIFO_DEPTH - 4,
            RAM_BLOCK_TYPE    => "M10K"
        )
        port map (
            clk         => clk,
            rst         => rst,
            wr_en       => cmd_tx_start,
            wr_data     => cmd_tx_byte,
            rd_en       => tx_fifo_rd_en,
            rd_data     => tx_fifo_rd_data,
            empty       => tx_fifo_empty,
            full        => tx_fifo_full,
            almost_full => tx_fifo_almost_full,
            overflow    => tx_fifo_overflow,
            underflow   => tx_fifo_underflow
        );

    u_command : entity work.command_interface
        generic map (
            ADDR_WIDTH        => ADDR_WIDTH,
            DATA_WIDTH        => HOST_DATA_WIDTH,
            COUNTER_WIDTH     => 64,
            HOST_READ_LATENCY => 3
        )
        port map (
            clk                      => clk,
            rst                      => rst,
            rx_valid                 => cmd_rx_valid,
            rx_byte                  => cmd_rx_byte,
            rx_ready                 => cmd_rx_ready,
            tx_busy                  => cmd_tx_busy,
            tx_start                 => cmd_tx_start,
            tx_byte                  => cmd_tx_byte,
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

    u_core : entity work.matrix_mult_tiled_core
        generic map (
            N                   => N,
            TILE_SIZE           => TILE_SIZE,
            NUM_MACS            => NUM_MACS,
            DATA_WIDTH          => DATA_WIDTH,
            ACC_WIDTH           => ACC_WIDTH,
            MEM_TYPE            => MEM_TYPE,
            DATAFLOW            => DATAFLOW,
            BUFFERING_MODE      => BUFFERING_MODE,
            MEMORY_BURST_LEN    => MEMORY_BURST_LEN,
            MAC_PIPELINE_STAGES => MAC_PIPELINE_STAGES,
            MEMORY_BANKS_A      => MEMORY_BANKS_A,
            MEMORY_BANKS_B      => MEMORY_BANKS_B
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
            result_addr => core_result_addr,
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

    -- Debug LEDs direto no top.
    -- Nao instanciar accelerator_status_leds ao mesmo tempo, para evitar dois drivers em LEDR.
    process(clk, rst)
    begin
        if rst = '1' then
            dbg_heartbeat_count <= 0;
            dbg_heartbeat_reg   <= '0';

            dbg_uart_rx_seen   <= '0';
            dbg_cmd_rx_seen    <= '0';
            dbg_cmd_tx_seen    <= '0';
            dbg_host_wr_seen   <= '0';
            dbg_cmd_start_seen <= '0';
            dbg_busy_seen      <= '0';
            dbg_done_seen      <= '0';
            dbg_host_rd_seen   <= '0';
            dbg_error_seen     <= '0';

        elsif rising_edge(clk) then
            if dbg_heartbeat_count = DBG_HEARTBEAT_TOGGLE_CYCLES-1 then
                dbg_heartbeat_count <= 0;
                dbg_heartbeat_reg <= not dbg_heartbeat_reg;
            else
                dbg_heartbeat_count <= dbg_heartbeat_count + 1;
            end if;

            if uart_rx_valid = '1' then
                dbg_uart_rx_seen <= '1';
            end if;

            if cmd_rx_valid = '1' then
                dbg_cmd_rx_seen <= '1';
            end if;

            if cmd_tx_start = '1' then
                dbg_cmd_tx_seen <= '1';
            end if;

            if host_wr_en = '1' then
                dbg_host_wr_seen <= '1';
            end if;

            if cmd_start = '1' then
                dbg_cmd_start_seen <= '1';
            end if;

            if accel_busy = '1' then
                dbg_busy_seen <= '1';
            end if;

            if accel_done = '1' then
                dbg_done_seen <= '1';
            end if;

            if host_rd_en = '1' then
                dbg_host_rd_seen <= '1';
            end if;

            if rx_fifo_overflow = '1' or rx_fifo_underflow = '1' or
               tx_fifo_overflow = '1' or tx_fifo_underflow = '1' or
               start_button = '1' then
                dbg_error_seen <= '1';
            end if;
        end if;
    end process;

    LEDR(0) <= dbg_heartbeat_reg;
    LEDR(1) <= dbg_uart_rx_seen;
    LEDR(2) <= dbg_cmd_rx_seen;
    LEDR(3) <= dbg_cmd_tx_seen;
    LEDR(4) <= dbg_host_wr_seen;
    LEDR(5) <= dbg_cmd_start_seen;
    LEDR(6) <= dbg_busy_seen;
    LEDR(7) <= dbg_done_seen;
    LEDR(8) <= dbg_host_rd_seen;
    LEDR(9) <= dbg_error_seen;

    u_sigma_hex : entity work.sigma_hex_display
        port map (
            running => accel_busy,
            HEX0    => HEX0,
            HEX1    => HEX1,
            HEX2    => HEX2,
            HEX3    => HEX3,
            HEX4    => HEX4,
            HEX5    => HEX5
        );

    debug_probe_data(0) <= accel_start;
    debug_probe_data(1) <= accel_busy;
    debug_probe_data(2) <= accel_done;
    debug_probe_data(3) <= done_seen;
    debug_probe_data(4) <= uart_rx_valid;
    debug_probe_data(5) <= rx_fifo_full;
    debug_probe_data(6) <= rx_fifo_almost_full;
    debug_probe_data(7) <= rx_fifo_overflow;
    debug_probe_data(8) <= cmd_rx_valid;
    debug_probe_data(9) <= cmd_rx_ready;
    debug_probe_data(10) <= cmd_tx_start;
    debug_probe_data(11) <= tx_fifo_full;
    debug_probe_data(12) <= tx_fifo_almost_full;
    debug_probe_data(13) <= tx_fifo_overflow;
    debug_probe_data(14) <= host_wr_en;
    debug_probe_data(15) <= host_rd_en;
    debug_probe_data(17 downto 16) <= host_matrix_sel;
    debug_probe_data(31 downto 18) <= std_logic_vector(resize(host_addr, 14));
    debug_probe_data(39 downto 32) <= cmd_rx_byte;
    debug_probe_data(47 downto 40) <= cmd_tx_byte;
    debug_probe_data(55 downto 48) <= tx_fifo_rd_data;
    debug_probe_data(63 downto 56) <= uart_rx_byte;
    debug_probe_data(95 downto 64) <= std_logic_vector(perf_total_cycles(31 downto 0));
    debug_probe_data(127 downto 96) <= std_logic_vector(perf_num_tiles_processed(31 downto 0));

    debug_trigger_data(0) <= accel_start;
    debug_trigger_data(1) <= accel_busy;
    debug_trigger_data(2) <= accel_done;
    debug_trigger_data(3) <= uart_rx_valid;
    debug_trigger_data(4) <= cmd_rx_valid;
    debug_trigger_data(5) <= host_wr_en;
    debug_trigger_data(6) <= host_rd_en;
    debug_trigger_data(7) <= rx_fifo_overflow or tx_fifo_overflow;

    gen_signaltap : if ENABLE_SIGNALTAP generate
        u_signaltap : entity work.signaltap_debug_core
            generic map (
                DATA_BITS      => 128,
                TRIGGER_BITS   => 8,
                SAMPLE_DEPTH   => 512,
                MEM_ADDR_BITS  => 9,
                DATA_CNTR_BITS => 7
            )
            port map (
                clk          => clk,
                probe_data   => debug_probe_data,
                trigger_data => debug_trigger_data
            );
    end generate;

    process(clk, rst)
    begin
        if rst = '1' then
            done_seen <= '0';
            core_result_addr <= (others => '0');

        elsif rising_edge(clk) then
            if host_rd_en = '1' then
                core_result_addr <= host_rd_addr;
            end if;

            if accel_start = '1' then
                done_seen <= '0';
            elsif accel_done = '1' then
                done_seen <= '1';
            end if;
        end if;
    end process;

end architecture rtl;