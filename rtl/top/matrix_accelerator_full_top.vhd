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
        SDRAM_ADDR_W        : positive := 26;
        SDRAM_DATA_W        : positive := 32;
        SDRAM_SIMULATION_MODEL : boolean := false;
        SDRAM_CLK_PHASE_SHIFT_PS : string := "-3000";
        SDRAM_READ_TIMEOUT_CYCLES : positive := 100000;
        ACCUMULATE_C        : boolean := false;
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
        HEX5         : out std_logic_vector(6 downto 0);

        DRAM_ADDR  : out std_logic_vector(12 downto 0);
        DRAM_BA    : out std_logic_vector(1 downto 0);
        DRAM_CAS_N : out std_logic;
        DRAM_CKE   : out std_logic;
        DRAM_CLK   : out std_logic;
        DRAM_CS_N  : out std_logic;
        DRAM_DQ    : inout std_logic_vector(15 downto 0);
        DRAM_LDQM  : out std_logic;
        DRAM_RAS_N : out std_logic;
        DRAM_UDQM  : out std_logic;
        DRAM_WE_N  : out std_logic
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

    signal uart_tx_start  : std_logic;
    signal uart_tx_byte   : std_logic_vector(7 downto 0);
    signal uart_tx_busy   : std_logic;
    signal uart_tx_serial : std_logic;

    signal tx_fifo_rd_en       : std_logic := '0';
    signal tx_fifo_rd_data     : std_logic_vector(7 downto 0);
    signal tx_fifo_empty       : std_logic;
    signal tx_fifo_full        : std_logic;
    signal tx_fifo_almost_full : std_logic;
    signal tx_fifo_overflow    : std_logic;
    signal tx_fifo_underflow   : std_logic;

    type tx_state_t is (TX_IDLE, TX_START);
    signal tx_state    : tx_state_t := TX_IDLE;
    signal tx_byte_reg : std_logic_vector(7 downto 0) := (others => '0');

    signal cmd_start   : std_logic;
    signal cmd_clear   : std_logic;
    signal accel_start : std_logic;
    signal accel_rst   : std_logic;
    signal accel_busy  : std_logic;
    signal accel_done  : std_logic;
    signal done_seen   : std_logic := '0';
    signal accel_core_rst : std_logic;
    signal dram_clk_out   : std_logic;
    signal sdram_pll_locked : std_logic;

    signal host_cmd_valid  : std_logic;
    signal host_cmd_write  : std_logic;
    signal host_full_word_write : std_logic;
    signal host_cmd_ready  : std_logic;
    signal host_matrix_sel : std_logic_vector(1 downto 0);
    signal host_addr       : unsigned(ADDR_WIDTH-1 downto 0);
    signal host_data_in    : std_logic_vector(HOST_DATA_WIDTH-1 downto 0);
    signal host_data_out   : std_logic_vector(HOST_DATA_WIDTH-1 downto 0);
    signal host_rd_valid   : std_logic;

    signal accel_data_out   : signed(ACC_WIDTH-1 downto 0);

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
    signal status_memory_error   : std_logic;

    signal debug_probe_data   : std_logic_vector(127 downto 0) := (others => '0');
    signal debug_trigger_data : std_logic_vector(7 downto 0) := (others => '0');

    attribute keep : boolean;
    attribute preserve : boolean;
    attribute keep of debug_probe_data : signal is true;
    attribute keep of debug_trigger_data : signal is true;
    attribute preserve of debug_probe_data : signal is true;
    attribute preserve of debug_trigger_data : signal is true;

    constant DBG_HEARTBEAT_TOGGLE_CYCLES : positive := CLK_FREQ_HZ / 2;
    constant DBG_ACTIVITY_STRETCH_CYCLES : positive := CLK_FREQ_HZ / 4;

    signal dbg_heartbeat_count : natural range 0 to DBG_HEARTBEAT_TOGGLE_CYCLES-1 := 0;
    signal dbg_heartbeat_reg   : std_logic := '0';
    signal dbg_host_wr_count    : natural range 0 to DBG_ACTIVITY_STRETCH_CYCLES := 0;
    signal dbg_start_count      : natural range 0 to DBG_ACTIVITY_STRETCH_CYCLES := 0;
    signal dbg_load_count       : natural range 0 to DBG_ACTIVITY_STRETCH_CYCLES := 0;
    signal dbg_compute_count    : natural range 0 to DBG_ACTIVITY_STRETCH_CYCLES := 0;
    signal dbg_store_count      : natural range 0 to DBG_ACTIVITY_STRETCH_CYCLES := 0;
    signal dbg_host_read_count  : natural range 0 to DBG_ACTIVITY_STRETCH_CYCLES := 0;
    signal dbg_host_wr_visible   : std_logic;
    signal dbg_start_visible     : std_logic;
    signal dbg_load_visible      : std_logic;
    signal dbg_compute_visible   : std_logic;
    signal dbg_store_visible     : std_logic;
    signal dbg_host_read_visible : std_logic;

    signal dbg_uart_rx_line_seen : std_logic := '0';
    signal dbg_uart_rx_seen      : std_logic := '0';
    signal dbg_cmd_rx_seen       : std_logic := '0';
    signal dbg_cmd_tx_seen       : std_logic := '0';
    signal dbg_uart_tx_seen      : std_logic := '0';
    signal dbg_uart_tx_low_seen  : std_logic := '0';
    signal dbg_host_wr_seen      : std_logic := '0';
    signal dbg_host_read_seen    : std_logic := '0';
    signal dbg_host_rvalid_seen  : std_logic := '0';
    signal dbg_cmd_start_seen    : std_logic := '0';
    signal dbg_cmd_clear_seen    : std_logic := '0';
    signal dbg_done_seen         : std_logic := '0';
    signal dbg_error_seen        : std_logic := '0';
    signal dbg_stream_c_active   : std_logic := '0';
    signal dbg_wait_read_c       : std_logic := '0';
    signal system_error          : std_logic;

begin

    assert N mod TILE_SIZE = 0
        report "matrix_accelerator_full_top exige N multiplo de TILE_SIZE."
        severity failure;

    uart_tx_o <= uart_tx_serial;
    uart_tx_byte <= tx_byte_reg;

    accel_start <= cmd_start;
    -- Keep SDRAM/controller alive across host CLEAR commands.
    -- CLEAR is a protocol/session reset, not a board-level memory reset.
    accel_rst   <= rst;
    accel_core_rst <= accel_rst or (not sdram_pll_locked);
    DRAM_CLK <= dram_clk_out;

    host_data_out <= std_logic_vector(resize(accel_data_out, HOST_DATA_WIDTH));
    system_error <= dbg_error_seen or status_memory_error;
    dbg_host_wr_visible   <= '1' when dbg_host_wr_count /= 0 else '0';
    dbg_start_visible     <= '1' when dbg_start_count /= 0 else '0';
    dbg_load_visible      <= '1' when dbg_load_count /= 0 else '0';
    dbg_compute_visible   <= '1' when dbg_compute_count /= 0 else '0';
    dbg_store_visible     <= '1' when dbg_store_count /= 0 else '0';
    dbg_host_read_visible <= '1' when dbg_host_read_count /= 0 else '0';

    rx_fifo_rd_en <= cmd_rx_ready and not rx_fifo_empty;
    cmd_rx_valid  <= rx_fifo_rd_en;

    cmd_tx_busy <= tx_fifo_almost_full or tx_fifo_full;

    gen_sim_sdram_clock : if SDRAM_SIMULATION_MODEL generate
        dram_clk_out <= clk;
        sdram_pll_locked <= '1';
    end generate;

    gen_physical_sdram_clock : if not SDRAM_SIMULATION_MODEL generate
        u_sdram_clock_pll : entity work.sdram_clock_pll
            generic map (
                PHASE_SHIFT_PS => SDRAM_CLK_PHASE_SHIFT_PS
            )
            port map (
                clk_in    => clk,
                rst       => rst,
                sdram_clk => dram_clk_out,
                locked    => sdram_pll_locked
            );
    end generate;

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
            tx_serial => uart_tx_serial,
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

    process(clk, rst)
    begin
        if rst = '1' then
            tx_fifo_rd_en <= '0';
            uart_tx_start <= '0';
            tx_byte_reg   <= (others => '0');
            tx_state      <= TX_IDLE;

        elsif rising_edge(clk) then
            tx_fifo_rd_en <= '0';
            uart_tx_start <= '0';

            case tx_state is
                when TX_IDLE =>
                    if uart_tx_busy = '0' and tx_fifo_empty = '0' then
                        tx_byte_reg <= tx_fifo_rd_data;
                        tx_fifo_rd_en <= '1';
                        tx_state <= TX_START;
                    end if;

                when TX_START =>
                    if uart_tx_busy = '0' then
                        uart_tx_start <= '1';
                        tx_state <= TX_IDLE;
                    end if;
            end case;
        end if;
    end process;

    u_command : entity work.command_interface
        generic map (
            ADDR_WIDTH        => ADDR_WIDTH,
            DATA_WIDTH        => HOST_DATA_WIDTH,
            CLK_FREQ_HZ       => CLK_FREQ_HZ,
            COUNTER_WIDTH     => 64
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
            accelerator_load_active  => status_load_active,
            accelerator_compute_active => status_compute_active,
            accelerator_store_active => status_store_active,
            accelerator_error        => system_error,
            host_cmd_valid           => host_cmd_valid,
            host_cmd_write           => host_cmd_write,
            host_full_word_write     => host_full_word_write,
            host_cmd_ready           => host_cmd_ready,
            host_matrix_sel          => host_matrix_sel,
            host_addr                => host_addr,
            host_data_in             => host_data_in,
            host_data_out            => host_data_out,
            host_rd_valid            => host_rd_valid,
            start                    => cmd_start,
            clear                    => cmd_clear,
            perf_total_cycles        => perf_total_cycles,
            perf_load_cycles         => perf_load_cycles,
            perf_compute_cycles      => perf_compute_cycles,
            perf_store_cycles        => perf_store_cycles,
            perf_num_tiles_processed => perf_num_tiles_processed,
            perf_num_mac_ops_issued  => perf_num_mac_ops_issued,
            debug_stream_c_active    => dbg_stream_c_active,
            debug_wait_read_c        => dbg_wait_read_c
        );

    u_core : entity work.matrix_mult_sdram_tiled_core
        generic map (
            N                   => N,
            TILE_SIZE           => TILE_SIZE,
            NUM_MACS            => NUM_MACS,
            DATA_WIDTH          => DATA_WIDTH,
            ACC_WIDTH           => ACC_WIDTH,
            MEMORY_BANKS_A      => MEMORY_BANKS_A,
            MEMORY_BANKS_B      => MEMORY_BANKS_B,
            SDRAM_ADDR_W        => SDRAM_ADDR_W,
            SDRAM_DATA_W        => SDRAM_DATA_W,
            SDRAM_SIMULATION_MODEL => SDRAM_SIMULATION_MODEL,
            SDRAM_READ_TIMEOUT_CYCLES => SDRAM_READ_TIMEOUT_CYCLES,
            ACCUMULATE_C        => ACCUMULATE_C,
            BUFFERING_MODE      => BUFFERING_MODE,
            MAC_PIPELINE_STAGES => MAC_PIPELINE_STAGES
        )
        port map (
            clk         => clk,
            rst         => accel_core_rst,
            soft_clear  => cmd_clear,
            host_cmd_valid => host_cmd_valid,
            host_cmd_write => host_cmd_write,
            host_full_word_write => host_full_word_write,
            host_cmd_ready => host_cmd_ready,
            matrix_sel     => host_matrix_sel,
            cmd_addr       => host_addr,
            data_in        => host_data_in(SDRAM_DATA_W-1 downto 0),
            data_out       => accel_data_out,
            rd_valid       => host_rd_valid,
            start       => accel_start,
            busy        => accel_busy,
            done        => accel_done,
            load_active    => status_load_active,
            compute_active => status_compute_active,
            store_active   => status_store_active,
            tile_done      => status_tile_done,
            mac_ops_issued => mac_ops_issued,
            memory_error   => status_memory_error,
            dram_addr  => DRAM_ADDR,
            dram_ba    => DRAM_BA,
            dram_cas_n => DRAM_CAS_N,
            dram_cke   => DRAM_CKE,
            dram_clk   => open,
            dram_cs_n  => DRAM_CS_N,
            dram_dq    => DRAM_DQ,
            dram_ldqm  => DRAM_LDQM,
            dram_ras_n => DRAM_RAS_N,
            dram_udqm  => DRAM_UDQM,
            dram_we_n  => DRAM_WE_N
        );

    u_perf : entity work.perf_counters
        generic map (
            COUNTER_WIDTH => 64
        )
        port map (
            clk                   => clk,
            rst                   => accel_core_rst,
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

    process(clk, rst)
    begin
        if rst = '1' then
            dbg_heartbeat_count <= 0;
            dbg_heartbeat_reg   <= '0';
            dbg_host_wr_count   <= 0;
            dbg_start_count     <= 0;
            dbg_load_count      <= 0;
            dbg_compute_count   <= 0;
            dbg_store_count     <= 0;
            dbg_host_read_count <= 0;

            dbg_uart_rx_line_seen <= '0';
            dbg_uart_rx_seen     <= '0';
            dbg_cmd_rx_seen      <= '0';
            dbg_cmd_tx_seen      <= '0';
            dbg_uart_tx_seen     <= '0';
            dbg_uart_tx_low_seen <= '0';
            dbg_host_wr_seen     <= '0';
            dbg_host_read_seen   <= '0';
            dbg_host_rvalid_seen <= '0';
            dbg_cmd_start_seen   <= '0';
            dbg_cmd_clear_seen   <= '0';
            dbg_done_seen        <= '0';
            dbg_error_seen       <= '0';

        elsif rising_edge(clk) then
            if dbg_heartbeat_count = DBG_HEARTBEAT_TOGGLE_CYCLES-1 then
                dbg_heartbeat_count <= 0;
                dbg_heartbeat_reg <= not dbg_heartbeat_reg;
            else
                dbg_heartbeat_count <= dbg_heartbeat_count + 1;
            end if;

            if cmd_clear = '1' then
                dbg_uart_rx_line_seen <= '0';
                dbg_uart_rx_seen      <= '0';
                dbg_cmd_rx_seen       <= '0';
                dbg_cmd_tx_seen       <= '0';
                dbg_uart_tx_seen      <= '0';
                dbg_uart_tx_low_seen  <= '0';
                dbg_host_wr_seen      <= '0';
                dbg_host_read_seen    <= '0';
                dbg_host_rvalid_seen  <= '0';
                dbg_cmd_start_seen    <= '0';
                dbg_done_seen         <= '0';
                dbg_error_seen        <= '0';
                dbg_cmd_clear_seen    <= '1';
                dbg_host_wr_count     <= 0;
                dbg_start_count       <= 0;
                dbg_load_count        <= 0;
                dbg_compute_count     <= 0;
                dbg_store_count       <= 0;
                dbg_host_read_count   <= 0;
            end if;

            if cmd_clear = '0' and dbg_host_wr_count /= 0 then
                dbg_host_wr_count <= dbg_host_wr_count - 1;
            end if;

            if cmd_clear = '0' and dbg_start_count /= 0 then
                dbg_start_count <= dbg_start_count - 1;
            end if;

            if cmd_clear = '0' and dbg_load_count /= 0 then
                dbg_load_count <= dbg_load_count - 1;
            end if;

            if cmd_clear = '0' and dbg_compute_count /= 0 then
                dbg_compute_count <= dbg_compute_count - 1;
            end if;

            if cmd_clear = '0' and dbg_store_count /= 0 then
                dbg_store_count <= dbg_store_count - 1;
            end if;

            if cmd_clear = '0' and dbg_host_read_count /= 0 then
                dbg_host_read_count <= dbg_host_read_count - 1;
            end if;

            if uart_rx_i = '0' then
                dbg_uart_rx_line_seen <= '1';
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

            if uart_tx_start = '1' then
                dbg_uart_tx_seen <= '1';
            end if;

            if uart_tx_serial = '0' then
                dbg_uart_tx_low_seen <= '1';
            end if;

            if cmd_clear = '0' and host_cmd_valid = '1' and host_cmd_write = '1' and host_cmd_ready = '1' then
                dbg_host_wr_seen <= '1';
                dbg_host_wr_count <= DBG_ACTIVITY_STRETCH_CYCLES;
            end if;

            if host_cmd_valid = '1' and host_cmd_write = '0' and host_cmd_ready = '1' then
                dbg_host_read_seen <= '1';
            end if;

            if cmd_clear = '0' and host_rd_valid = '1' then
                dbg_host_rvalid_seen <= '1';
                dbg_host_read_count <= DBG_ACTIVITY_STRETCH_CYCLES;
            end if;

            if cmd_clear = '0' and cmd_start = '1' then
                dbg_cmd_start_seen <= '1';
                dbg_start_count <= DBG_ACTIVITY_STRETCH_CYCLES;
            end if;

            if cmd_clear = '1' then
                dbg_cmd_clear_seen <= '1';
            end if;

            if accel_done = '1' or done_seen = '1' then
                dbg_done_seen <= '1';
            end if;

            if cmd_clear = '0' and status_load_active = '1' then
                dbg_load_count <= DBG_ACTIVITY_STRETCH_CYCLES;
            end if;

            if cmd_clear = '0' and status_compute_active = '1' then
                dbg_compute_count <= DBG_ACTIVITY_STRETCH_CYCLES;
            end if;

            if cmd_clear = '0' and status_store_active = '1' then
                dbg_store_count <= DBG_ACTIVITY_STRETCH_CYCLES;
            end if;

            if status_memory_error = '1' or rx_fifo_overflow = '1' or rx_fifo_underflow = '1' or
            tx_fifo_overflow = '1' or tx_fifo_underflow = '1' then
                dbg_error_seen <= '1';
            end if;
        end if;
    end process;

    -- Debug LED map for board bring-up and SDRAM diagnosis:
    -- LEDR0: heartbeat/clock alive.
    -- LEDR1: SDRAM PLL locked.
    -- LEDR2: host write accepted, usually A/B streaming into SDRAM.
    -- LEDR3: START command accepted.
    -- LEDR4: tile load phase active, SDRAM -> M10K.
    -- LEDR5: compute phase active.
    -- LEDR6: tile store phase active, M10K -> SDRAM.
    -- LEDR7: host read returned data, usually C streaming out.
    -- LEDR8: done latched.
    -- LEDR9: FIFO/protocol/SDRAM error latch, cleared by CLEAR or board reset.
    LEDR(0) <= dbg_heartbeat_reg;
    LEDR(1) <= sdram_pll_locked;
    LEDR(2) <= dbg_host_wr_visible or dbg_host_wr_seen;
    LEDR(3) <= dbg_start_visible or dbg_cmd_start_seen;
    LEDR(4) <= dbg_load_visible;
    LEDR(5) <= dbg_compute_visible;
    LEDR(6) <= dbg_store_visible;
    LEDR(7) <= dbg_host_read_visible;
    LEDR(8) <= dbg_done_seen;
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
    debug_probe_data(5) <= uart_rx_i;
    debug_probe_data(6) <= rx_fifo_almost_full;
    debug_probe_data(7) <= rx_fifo_overflow;
    debug_probe_data(8) <= cmd_rx_valid;
    debug_probe_data(9) <= cmd_rx_ready;
    debug_probe_data(10) <= cmd_tx_start;
    debug_probe_data(11) <= tx_fifo_full;
    debug_probe_data(12) <= tx_fifo_almost_full;
    debug_probe_data(13) <= tx_fifo_overflow;
    debug_probe_data(14) <= host_cmd_valid;
    debug_probe_data(15) <= host_cmd_write;
    debug_probe_data(16) <= cmd_start;
    debug_probe_data(17) <= cmd_clear;
    debug_probe_data(18) <= status_load_active;
    debug_probe_data(19) <= status_compute_active;
    debug_probe_data(20) <= status_store_active;
    debug_probe_data(21) <= status_tile_done;
    debug_probe_data(22) <= status_memory_error;
    debug_probe_data(23) <= sdram_pll_locked;
    debug_probe_data(31 downto 24) <= std_logic_vector(resize(host_addr, 8));
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
    debug_trigger_data(5) <= host_cmd_valid and host_cmd_write and host_cmd_ready;
    debug_trigger_data(6) <= host_cmd_valid and (not host_cmd_write) and host_cmd_ready;
    debug_trigger_data(7) <= status_memory_error or rx_fifo_overflow or tx_fifo_overflow or cmd_clear;

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

        elsif rising_edge(clk) then
            if cmd_clear = '1' then
                done_seen <= '0';
            else
                if accel_start = '1' then
                    done_seen <= '0';
                elsif accel_done = '1' then
                    done_seen <= '1';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
