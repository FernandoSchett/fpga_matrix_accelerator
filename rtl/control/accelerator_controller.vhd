library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;
use work.matrix_accel_config_pkg.all;

entity accelerator_controller is
    generic (
        N                : positive := DEFAULT_N;
        TILE_SIZE        : positive := DEFAULT_TILE_SIZE;
        NUM_MACS         : positive := DEFAULT_NUM_MACS;
        DATA_WIDTH       : positive := DEFAULT_DATA_WIDTH;
        ACC_WIDTH        : positive := DEFAULT_ACC_WIDTH;
        SDRAM_DATA_WIDTH : positive := DEFAULT_SDRAM_DATA_WIDTH;
        SDRAM_ADDR_WIDTH : positive := DEFAULT_SDRAM_ADDR_WIDTH
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start : in std_logic;
        busy  : out std_logic;
        done  : out std_logic;

        sdram_rd_req   : out std_logic;
        sdram_rd_addr  : out unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
        sdram_rd_data  : in std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
        sdram_rd_valid : in std_logic;
        sdram_rd_ready : in std_logic;

        sdram_wr_req   : out std_logic;
        sdram_wr_addr  : out unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
        sdram_wr_data  : out std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
        sdram_wr_ready : in std_logic;

        sdram_busy : in std_logic;

        event_sdram_read  : out std_logic;
        event_sdram_write : out std_logic;
        event_mac_group   : out std_logic;

        perf_total_cycles        : out unsigned(63 downto 0);
        perf_load_cycles         : out unsigned(63 downto 0);
        perf_compute_cycles      : out unsigned(63 downto 0);
        perf_store_cycles        : out unsigned(63 downto 0);
        perf_num_tiles_processed : out unsigned(63 downto 0);
        perf_num_mac_ops_issued  : out unsigned(63 downto 0);

        status_load_active    : out std_logic;
        status_compute_active : out std_logic;
        status_store_active   : out std_logic;
        status_tile_done      : out std_logic
    );
end entity accelerator_controller;

architecture rtl of accelerator_controller is

    constant MATRIX_ELEMS : positive := N * N;
    constant TILE_ELEMS   : positive := TILE_SIZE * TILE_SIZE;
    constant NUM_TILES    : positive := N / TILE_SIZE;
    constant TILE_IDX_W   : positive := clog2(NUM_TILES + 1);
    constant LOCAL_IDX_W  : positive := clog2(TILE_SIZE);

    constant C_BASE : natural := MATRIX_ELEMS * 2;

    subtype data_t is signed(DATA_WIDTH-1 downto 0);
    subtype acc_t  is signed(ACC_WIDTH-1 downto 0);

    type data_tile_t is array (0 to TILE_ELEMS-1) of data_t;
    type acc_tile_t is array (0 to TILE_ELEMS-1) of acc_t;

    type compute_state_t is (
        COMP_IDLE,
        COMP_SET_READ_ADDR,
        COMP_WAIT_READ,
        COMP_CAPTURE_READ,
        COMP_START_CORE,
        COMP_WAIT_CORE,
        COMP_CAPTURE_CORE,
        COMP_SET_WRITE_ADDR,
        COMP_WRITE_HOLD,
        COMP_DONE
    );

    signal sched_load_done    : std_logic;
    signal sched_compute_done : std_logic := '0';
    signal sched_store_done   : std_logic;

    signal sched_busy          : std_logic;
    signal sched_done          : std_logic;
    signal sched_init_c_tile   : std_logic;
    signal sched_load_start    : std_logic;
    signal sched_compute_start : std_logic;
    signal sched_store_start   : std_logic;
    signal sched_tile_i        : unsigned(TILE_IDX_W-1 downto 0);
    signal sched_tile_j        : unsigned(TILE_IDX_W-1 downto 0);
    signal sched_tile_k        : unsigned(TILE_IDX_W-1 downto 0);

    signal loader_busy : std_logic;
    signal loader_done : std_logic;
    signal loader_rd_req  : std_logic;
    signal loader_rd_addr : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);

    signal loader_a_wr_en    : std_logic;
    signal loader_a_row      : unsigned(LOCAL_IDX_W-1 downto 0);
    signal loader_a_col      : unsigned(LOCAL_IDX_W-1 downto 0);
    signal loader_a_wr_data  : data_t;
    signal loader_b_wr_en    : std_logic;
    signal loader_b_row      : unsigned(LOCAL_IDX_W-1 downto 0);
    signal loader_b_col      : unsigned(LOCAL_IDX_W-1 downto 0);
    signal loader_b_wr_data  : data_t;

    signal store_busy : std_logic;
    signal store_done : std_logic;
    signal store_wr_req  : std_logic;
    signal store_wr_addr : unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
    signal store_wr_data : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
    signal store_c_row   : unsigned(LOCAL_IDX_W-1 downto 0);
    signal store_c_col   : unsigned(LOCAL_IDX_W-1 downto 0);

    signal a_buf_row      : unsigned(LOCAL_IDX_W-1 downto 0) := (others => '0');
    signal a_buf_col      : unsigned(LOCAL_IDX_W-1 downto 0) := (others => '0');
    signal a_buf_wr_en    : std_logic := '0';
    signal a_buf_wr_data  : data_t := (others => '0');
    signal a_buf_rd_data  : data_t;
    signal a_buf_addr_dbg : unsigned(clog2(TILE_ELEMS)-1 downto 0);

    signal b_buf_row      : unsigned(LOCAL_IDX_W-1 downto 0) := (others => '0');
    signal b_buf_col      : unsigned(LOCAL_IDX_W-1 downto 0) := (others => '0');
    signal b_buf_wr_en    : std_logic := '0';
    signal b_buf_wr_data  : data_t := (others => '0');
    signal b_buf_rd_data  : data_t;
    signal b_buf_addr_dbg : unsigned(clog2(TILE_ELEMS)-1 downto 0);

    signal c_buf_row      : unsigned(LOCAL_IDX_W-1 downto 0) := (others => '0');
    signal c_buf_col      : unsigned(LOCAL_IDX_W-1 downto 0) := (others => '0');
    signal c_buf_wr_en    : std_logic := '0';
    signal c_buf_wr_data  : acc_t := (others => '0');
    signal c_buf_rd_data  : acc_t;
    signal c_buf_addr_dbg : unsigned(clog2(TILE_ELEMS)-1 downto 0);

    signal compute_state      : compute_state_t := COMP_IDLE;
    signal compute_idx        : integer range 0 to TILE_ELEMS-1 := 0;
    signal compute_local_row  : unsigned(LOCAL_IDX_W-1 downto 0) := (others => '0');
    signal compute_local_col  : unsigned(LOCAL_IDX_W-1 downto 0) := (others => '0');
    signal compute_c_wr_en    : std_logic := '0';
    signal compute_c_wr_data  : acc_t := (others => '0');
    signal compute_done_reg   : std_logic := '0';

    signal a_tile_reg      : data_tile_t := (others => (others => '0'));
    signal b_tile_reg      : data_tile_t := (others => (others => '0'));
    signal c_tile_reg      : acc_tile_t := (others => (others => '0'));
    signal c_tile_result   : acc_tile_t := (others => (others => '0'));

    signal core_start      : std_logic := '0';
    signal core_done       : std_logic;
    signal core_a_tile     : std_logic_vector((TILE_ELEMS*DATA_WIDTH)-1 downto 0);
    signal core_b_tile     : std_logic_vector((TILE_ELEMS*DATA_WIDTH)-1 downto 0);
    signal core_c_tile_in  : std_logic_vector((TILE_ELEMS*ACC_WIDTH)-1 downto 0);
    signal core_c_tile_out : std_logic_vector((TILE_ELEMS*ACC_WIDTH)-1 downto 0);

    signal loader_active : std_logic;
    signal store_active  : std_logic;

    signal perf_compute_active : std_logic;
    signal perf_tile_done      : std_logic;
    signal perf_mac_ops_issued_cycle : unsigned(63 downto 0);
    signal store_done_d : std_logic := '0';

    function pack_data_tile(constant tile : data_tile_t) return std_logic_vector is
        variable result : std_logic_vector((TILE_ELEMS*DATA_WIDTH)-1 downto 0);
        variable left_i : natural;
    begin
        for idx in 0 to TILE_ELEMS-1 loop
            left_i := ((idx + 1) * DATA_WIDTH) - 1;
            result(left_i downto left_i - DATA_WIDTH + 1) := std_logic_vector(tile(idx));
        end loop;

        return result;
    end function;

    function pack_acc_tile(constant tile : acc_tile_t) return std_logic_vector is
        variable result : std_logic_vector((TILE_ELEMS*ACC_WIDTH)-1 downto 0);
        variable left_i : natural;
    begin
        for idx in 0 to TILE_ELEMS-1 loop
            left_i := ((idx + 1) * ACC_WIDTH) - 1;
            result(left_i downto left_i - ACC_WIDTH + 1) := std_logic_vector(tile(idx));
        end loop;

        return result;
    end function;

    function get_acc_from_flat(
        constant flat : std_logic_vector;
        constant idx  : natural
    ) return acc_t is
        variable result : acc_t;
        variable left_i : natural;
    begin
        left_i := ((idx + 1) * ACC_WIDTH) - 1;
        result := signed(flat(left_i downto left_i - ACC_WIDTH + 1));
        return result;
    end function;

begin

    assert N mod TILE_SIZE = 0
        report "accelerator_controller exige N multiplo de TILE_SIZE."
        severity failure;

    assert SDRAM_DATA_WIDTH >= ACC_WIDTH
        report "accelerator_controller exige SDRAM_DATA_WIDTH >= ACC_WIDTH."
        severity failure;

    busy <= sched_busy;
    done <= sched_done;

    sched_load_done    <= loader_done;
    sched_compute_done <= compute_done_reg;
    sched_store_done   <= store_done;

    loader_active <= loader_busy or sched_load_start;
    store_active  <= store_busy or sched_store_start;

    sdram_rd_req  <= loader_rd_req;
    sdram_rd_addr <= loader_rd_addr;
    sdram_wr_req  <= store_wr_req;
    sdram_wr_addr <= store_wr_addr + to_unsigned(C_BASE, SDRAM_ADDR_WIDTH);
    sdram_wr_data <= store_wr_data;

    event_sdram_read  <= loader_rd_req;
    event_sdram_write <= store_wr_req;
    event_mac_group   <= core_start;

    perf_compute_active <= '1' when compute_state /= COMP_IDLE and compute_state /= COMP_DONE else '0';
    perf_tile_done <= store_done and not store_done_d;
    perf_mac_ops_issued_cycle <= to_unsigned(TILE_SIZE * TILE_SIZE * TILE_SIZE, 64) when core_start = '1' else
                                 (others => '0');

    status_load_active    <= loader_busy;
    status_compute_active <= perf_compute_active;
    status_store_active   <= store_busy;
    status_tile_done      <= perf_tile_done;

    a_buf_row     <= loader_a_row when loader_active = '1' else compute_local_row;
    a_buf_col     <= loader_a_col when loader_active = '1' else compute_local_col;
    a_buf_wr_en   <= loader_a_wr_en when loader_active = '1' else '0';
    a_buf_wr_data <= loader_a_wr_data;

    b_buf_row     <= loader_b_row when loader_active = '1' else compute_local_row;
    b_buf_col     <= loader_b_col when loader_active = '1' else compute_local_col;
    b_buf_wr_en   <= loader_b_wr_en when loader_active = '1' else '0';
    b_buf_wr_data <= loader_b_wr_data;

    c_buf_row     <= store_c_row when store_active = '1' else compute_local_row;
    c_buf_col     <= store_c_col when store_active = '1' else compute_local_col;
    c_buf_wr_en   <= '0' when store_active = '1' else compute_c_wr_en;
    c_buf_wr_data <= compute_c_wr_data;

    core_a_tile    <= pack_data_tile(a_tile_reg);
    core_b_tile    <= pack_data_tile(b_tile_reg);
    core_c_tile_in <= pack_acc_tile(c_tile_reg);

    u_scheduler : entity work.tile_scheduler
        generic map (
            N         => N,
            TILE_SIZE => TILE_SIZE
        )
        port map (
            clk           => clk,
            rst           => rst,
            start         => start,
            load_done     => sched_load_done,
            compute_done  => sched_compute_done,
            store_done    => sched_store_done,
            busy          => sched_busy,
            done          => sched_done,
            init_c_tile   => sched_init_c_tile,
            load_start    => sched_load_start,
            compute_start => sched_compute_start,
            store_start   => sched_store_start,
            tile_i        => sched_tile_i,
            tile_j        => sched_tile_j,
            tile_k        => sched_tile_k
        );

    u_loader : entity work.tile_loader
        generic map (
            N                => N,
            TILE_SIZE        => TILE_SIZE,
            DATA_WIDTH       => DATA_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH
        )
        port map (
            clk              => clk,
            rst              => rst,
            start            => sched_load_start,
            tile_i           => sched_tile_i,
            tile_j           => sched_tile_j,
            tile_k           => sched_tile_k,
            busy             => loader_busy,
            done             => loader_done,
            sdram_rd_req     => loader_rd_req,
            sdram_rd_addr    => loader_rd_addr,
            sdram_rd_data    => sdram_rd_data,
            sdram_rd_valid   => sdram_rd_valid,
            sdram_rd_ready   => sdram_rd_ready,
            sdram_busy       => sdram_busy,
            tile_a_wr_en     => loader_a_wr_en,
            tile_a_local_row => loader_a_row,
            tile_a_local_col => loader_a_col,
            tile_a_wr_data   => loader_a_wr_data,
            tile_b_wr_en     => loader_b_wr_en,
            tile_b_local_row => loader_b_row,
            tile_b_local_col => loader_b_col,
            tile_b_wr_data   => loader_b_wr_data
        );

    u_store : entity work.tile_store
        generic map (
            N                => N,
            TILE_SIZE        => TILE_SIZE,
            ACC_WIDTH        => ACC_WIDTH,
            SDRAM_DATA_WIDTH => SDRAM_DATA_WIDTH,
            SDRAM_ADDR_WIDTH => SDRAM_ADDR_WIDTH
        )
        port map (
            clk              => clk,
            rst              => rst,
            start            => sched_store_start,
            tile_i           => sched_tile_i,
            tile_j           => sched_tile_j,
            busy             => store_busy,
            done             => store_done,
            sdram_wr_req     => store_wr_req,
            sdram_wr_addr    => store_wr_addr,
            sdram_wr_data    => store_wr_data,
            sdram_wr_ready   => sdram_wr_ready,
            sdram_busy       => sdram_busy,
            tile_c_local_row => store_c_row,
            tile_c_local_col => store_c_col,
            tile_c_rd_data   => c_buf_rd_data
        );

    u_buf_a : entity work.tile_buffer_m10k
        generic map (
            TILE_SIZE     => TILE_SIZE,
            DATA_WIDTH    => DATA_WIDTH,
            ACC_WIDTH     => ACC_WIDTH,
            USE_M10K      => true,
            IS_ACC_BUFFER => false,
            BUFFER_IMPL   => "INFERRED"
        )
        port map (
            clk            => clk,
            rst            => rst,
            wr_en          => a_buf_wr_en,
            local_row      => a_buf_row,
            local_col      => a_buf_col,
            wr_data        => a_buf_wr_data,
            rd_data        => a_buf_rd_data,
            local_addr_dbg => a_buf_addr_dbg
        );

    u_buf_b : entity work.tile_buffer_m10k
        generic map (
            TILE_SIZE     => TILE_SIZE,
            DATA_WIDTH    => DATA_WIDTH,
            ACC_WIDTH     => ACC_WIDTH,
            USE_M10K      => true,
            IS_ACC_BUFFER => false,
            BUFFER_IMPL   => "INFERRED"
        )
        port map (
            clk            => clk,
            rst            => rst,
            wr_en          => b_buf_wr_en,
            local_row      => b_buf_row,
            local_col      => b_buf_col,
            wr_data        => b_buf_wr_data,
            rd_data        => b_buf_rd_data,
            local_addr_dbg => b_buf_addr_dbg
        );

    u_buf_c : entity work.tile_buffer_m10k
        generic map (
            TILE_SIZE     => TILE_SIZE,
            DATA_WIDTH    => DATA_WIDTH,
            ACC_WIDTH     => ACC_WIDTH,
            USE_M10K      => true,
            IS_ACC_BUFFER => true,
            BUFFER_IMPL   => "INFERRED"
        )
        port map (
            clk            => clk,
            rst            => rst,
            wr_en          => c_buf_wr_en,
            local_row      => c_buf_row,
            local_col      => c_buf_col,
            wr_data        => c_buf_wr_data,
            rd_data        => c_buf_rd_data,
            local_addr_dbg => c_buf_addr_dbg
        );

    u_compute : entity work.matrix_tiled_compute_core
        generic map (
            TILE_SIZE  => TILE_SIZE,
            NUM_MACS   => NUM_MACS,
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH
        )
        port map (
            clk        => clk,
            rst        => rst,
            start      => core_start,
            done       => core_done,
            a_tile     => core_a_tile,
            b_tile     => core_b_tile,
            c_tile_in  => core_c_tile_in,
            c_tile_out => core_c_tile_out
        );

    u_perf : entity work.perf_counters
        generic map (
            COUNTER_WIDTH => 64
        )
        port map (
            clk                   => clk,
            rst                   => rst,
            start_count           => start,
            stop_count            => sched_done,
            load_active           => loader_busy,
            compute_active        => perf_compute_active,
            store_active          => store_busy,
            tile_done             => perf_tile_done,
            mac_ops_issued        => perf_mac_ops_issued_cycle,
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
            store_done_d <= '0';
        elsif rising_edge(clk) then
            store_done_d <= store_done;
        end if;
    end process;

    process(clk, rst)
        variable local_row : natural;
        variable local_col : natural;
    begin
        if rst = '1' then
            compute_state     <= COMP_IDLE;
            compute_idx       <= 0;
            compute_local_row <= (others => '0');
            compute_local_col <= (others => '0');
            compute_c_wr_en   <= '0';
            compute_c_wr_data <= (others => '0');
            compute_done_reg  <= '0';
            core_start        <= '0';
            a_tile_reg        <= (others => (others => '0'));
            b_tile_reg        <= (others => (others => '0'));
            c_tile_reg        <= (others => (others => '0'));
            c_tile_result     <= (others => (others => '0'));

        elsif rising_edge(clk) then
            core_start       <= '0';
            compute_c_wr_en  <= '0';
            compute_done_reg <= '0';

            case compute_state is
                when COMP_IDLE =>
                    compute_idx <= 0;

                    if sched_compute_start = '1' then
                        compute_state <= COMP_SET_READ_ADDR;
                    end if;

                when COMP_SET_READ_ADDR =>
                    local_row := compute_idx / TILE_SIZE;
                    local_col := compute_idx mod TILE_SIZE;

                    compute_local_row <= to_unsigned(local_row, compute_local_row'length);
                    compute_local_col <= to_unsigned(local_col, compute_local_col'length);
                    compute_state     <= COMP_WAIT_READ;

                when COMP_WAIT_READ =>
                    compute_state <= COMP_CAPTURE_READ;

                when COMP_CAPTURE_READ =>
                    a_tile_reg(compute_idx) <= a_buf_rd_data;
                    b_tile_reg(compute_idx) <= b_buf_rd_data;

                    if to_integer(sched_tile_k) = 0 then
                        c_tile_reg(compute_idx) <= (others => '0');
                    else
                        c_tile_reg(compute_idx) <= c_buf_rd_data;
                    end if;

                    if compute_idx = TILE_ELEMS-1 then
                        compute_idx   <= 0;
                        compute_state <= COMP_START_CORE;
                    else
                        compute_idx   <= compute_idx + 1;
                        compute_state <= COMP_SET_READ_ADDR;
                    end if;

                when COMP_START_CORE =>
                    core_start    <= '1';
                    compute_state <= COMP_WAIT_CORE;

                when COMP_WAIT_CORE =>
                    if core_done = '1' then
                        compute_state <= COMP_CAPTURE_CORE;
                    end if;

                when COMP_CAPTURE_CORE =>
                    for idx in 0 to TILE_ELEMS-1 loop
                        c_tile_result(idx) <= get_acc_from_flat(core_c_tile_out, idx);
                    end loop;

                    compute_idx   <= 0;
                    compute_state <= COMP_SET_WRITE_ADDR;

                when COMP_SET_WRITE_ADDR =>
                    local_row := compute_idx / TILE_SIZE;
                    local_col := compute_idx mod TILE_SIZE;

                    compute_local_row <= to_unsigned(local_row, compute_local_row'length);
                    compute_local_col <= to_unsigned(local_col, compute_local_col'length);
                    compute_c_wr_data <= c_tile_result(compute_idx);
                    compute_c_wr_en   <= '1';
                    compute_state     <= COMP_WRITE_HOLD;

                when COMP_WRITE_HOLD =>
                    if compute_idx = TILE_ELEMS-1 then
                        compute_done_reg <= '1';
                        compute_state    <= COMP_DONE;
                    else
                        compute_idx   <= compute_idx + 1;
                        compute_state <= COMP_SET_WRITE_ADDR;
                    end if;

                when COMP_DONE =>
                    compute_done_reg <= '1';

                    if sched_compute_start = '0' then
                        compute_state <= COMP_IDLE;
                    end if;
            end case;
        end if;
    end process;

end architecture rtl;
