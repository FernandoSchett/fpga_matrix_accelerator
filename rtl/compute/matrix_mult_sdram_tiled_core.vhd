library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_accel_config_pkg.all;
use work.matrix_tiled_pkg.all;
use work.matrix_memory_map_pkg.all;

entity matrix_mult_sdram_tiled_core is
    generic (
        N                   : positive := 128;
        TILE_SIZE           : positive := 4;
        NUM_MACS            : positive := 4;
        DATA_WIDTH          : positive := 8;
        ACC_WIDTH           : positive := 32;
        MEMORY_BANKS_A      : positive := 1;
        MEMORY_BANKS_B      : positive := 1;
        SDRAM_ADDR_W        : positive := 26;
        SDRAM_DATA_W        : positive := 32;
        SDRAM_SIMULATION_MODEL : boolean := true;
        ACCUMULATE_C        : boolean := false;
        BASE_A_BYTES        : natural := 0;
        BASE_B_BYTES        : natural := 0;
        BASE_C_BYTES        : natural := 0;
        MAC_PIPELINE_STAGES : natural := 0;
        SDRAM_READ_TIMEOUT_CYCLES : natural := 100000
    );
    port (
        clk : in std_logic;
        rst : in std_logic;
        soft_clear : in std_logic;

        host_cmd_valid : in std_logic;
        host_cmd_write : in std_logic;
        host_cmd_ready : out std_logic;
        matrix_sel     : in std_logic_vector(1 downto 0);
        cmd_addr       : in unsigned(clog2(N*N)-1 downto 0);
        data_in        : in signed(DATA_WIDTH-1 downto 0);

        data_out : out signed(ACC_WIDTH-1 downto 0);
        rd_valid : out std_logic;

        start : in std_logic;
        busy  : out std_logic;
        done  : out std_logic;

        load_active    : out std_logic;
        compute_active : out std_logic;
        store_active   : out std_logic;
        tile_done      : out std_logic;
        mac_ops_issued : out unsigned(63 downto 0);
        memory_error   : out std_logic;

        dram_addr  : out std_logic_vector(12 downto 0);
        dram_ba    : out std_logic_vector(1 downto 0);
        dram_cas_n : out std_logic;
        dram_cke   : out std_logic;
        dram_clk   : out std_logic;
        dram_cs_n  : out std_logic;
        dram_dq    : inout std_logic_vector(15 downto 0);
        dram_ldqm  : out std_logic;
        dram_ras_n : out std_logic;
        dram_udqm  : out std_logic;
        dram_we_n  : out std_logic
    );
end entity matrix_mult_sdram_tiled_core;

architecture rtl of matrix_mult_sdram_tiled_core is

    function min_positive(left_value : positive; right_value : positive) return positive is
    begin
        if left_value < right_value then
            return left_value;
        end if;
        return right_value;
    end function;

    constant HOST_ADDR_W    : positive := clog2(N * N);
    constant LOCAL_W        : positive := clog2(TILE_SIZE);
    constant TILE_ELEMS     : positive := TILE_SIZE * TILE_SIZE;
    constant PANEL_TILES    : positive := min_positive(MEMORY_BANKS_A, MEMORY_BANKS_B);
    constant SDRAM_BYTES    : positive := SDRAM_DATA_W / 8;
    constant ACC_BYTES      : positive := matrix_elem_bytes(ACC_WIDTH);
    constant MATRIX_ELEMS   : natural := N * N;
    constant SELECT_BASE_C  : natural := matrix_base_c(N, DATA_WIDTH, ACC_WIDTH,
                                                        BASE_A_BYTES, BASE_B_BYTES, BASE_C_BYTES);
    constant TOTAL_BYTES    : natural := SELECT_BASE_C + (MATRIX_ELEMS * ACC_BYTES);
    constant EMULATED_WORDS : positive := ceil_div(TOTAL_BYTES, SDRAM_BYTES);

    type compute_state_t is (
        COMPUTE_IDLE,
        PACK_SETUP,
        PACK_WAIT,
        PACK_CAPTURE,
        START_CORE,
        WAIT_CORE,
        UNPACK_WRITE,
        COMPUTE_DONE_STATE
    );

    signal compute_state : compute_state_t := COMPUTE_IDLE;
    signal pack_idx      : natural range 0 to TILE_ELEMS-1 := 0;
    signal unpack_idx    : natural range 0 to TILE_ELEMS-1 := 0;

    signal sched_busy          : std_logic;
    signal sched_done          : std_logic;
    signal sched_tile_i        : natural range 0 to (N/TILE_SIZE)-1;
    signal sched_tile_j        : natural range 0 to (N/TILE_SIZE)-1;
    signal sched_tile_k        : natural range 0 to (N/TILE_SIZE)-1;
    signal sched_panel_count   : natural range 1 to PANEL_TILES;
    signal sched_load_c        : std_logic;
    signal sched_loader_start  : std_logic;
    signal sched_loader_done   : std_logic;
    signal sched_compute_start : std_logic;
    signal sched_compute_done  : std_logic := '0';
    signal sched_writer_start  : std_logic;
    signal sched_writer_done   : std_logic;

    signal host_pending : std_logic := '0';
    signal host_write_reg : std_logic := '0';
    signal host_addr_reg  : unsigned(SDRAM_ADDR_W-1 downto 0) := (others => '0');
    signal host_wdata_reg : std_logic_vector(SDRAM_DATA_W-1 downto 0) := (others => '0');
    signal host_be_reg    : std_logic_vector((SDRAM_DATA_W/8)-1 downto 0) := (others => '0');
    signal host_ready     : std_logic;
    signal host_rvalid    : std_logic;
    signal host_rdata     : std_logic_vector(SDRAM_DATA_W-1 downto 0);
    signal host_accept_ready : std_logic;
    signal data_out_reg   : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal data_out_valid_reg : std_logic := '0';

    signal loader_rd_req   : std_logic;
    signal loader_rd_addr  : unsigned(SDRAM_ADDR_W-1 downto 0);
    signal loader_rd_ready : std_logic;
    signal loader_rd_valid : std_logic;
    signal loader_rd_data  : std_logic_vector(SDRAM_DATA_W-1 downto 0);

    signal writer_wr_req   : std_logic;
    signal writer_wr_addr  : unsigned(SDRAM_ADDR_W-1 downto 0);
    signal writer_wr_data  : std_logic_vector(SDRAM_DATA_W-1 downto 0);
    signal writer_wr_be    : std_logic_vector((SDRAM_DATA_W/8)-1 downto 0);
    signal writer_wr_ready : std_logic;

    signal sdram_cmd_valid : std_logic;
    signal sdram_cmd_write : std_logic;
    signal sdram_cmd_addr  : unsigned(SDRAM_ADDR_W-1 downto 0);
    signal sdram_cmd_wdata : std_logic_vector(SDRAM_DATA_W-1 downto 0);
    signal sdram_cmd_be    : std_logic_vector((SDRAM_DATA_W/8)-1 downto 0);
    signal sdram_cmd_ready : std_logic;
    signal sdram_rd_valid  : std_logic;
    signal sdram_rd_data   : std_logic_vector(SDRAM_DATA_W-1 downto 0);
    signal sdram_busy      : std_logic;
    signal sdram_error     : std_logic;
    signal core_rst        : std_logic;

    signal loader_busy : std_logic;
    signal writer_busy : std_logic;

    signal loader_a_wr_en   : std_logic;
    signal loader_a_wr_row  : unsigned(LOCAL_W-1 downto 0);
    signal loader_a_wr_col  : unsigned(LOCAL_W-1 downto 0);
    signal loader_a_wr_bank : natural range 0 to PANEL_TILES-1;
    signal loader_a_wr_data : signed(DATA_WIDTH-1 downto 0);

    signal loader_b_wr_en   : std_logic;
    signal loader_b_wr_row  : unsigned(LOCAL_W-1 downto 0);
    signal loader_b_wr_col  : unsigned(LOCAL_W-1 downto 0);
    signal loader_b_wr_bank : natural range 0 to PANEL_TILES-1;
    signal loader_b_wr_data : signed(DATA_WIDTH-1 downto 0);

    signal loader_c_wr_en   : std_logic;
    signal loader_c_wr_row  : unsigned(LOCAL_W-1 downto 0);
    signal loader_c_wr_col  : unsigned(LOCAL_W-1 downto 0);
    signal loader_c_wr_data : signed(ACC_WIDTH-1 downto 0);

    signal a_rd_row  : unsigned(LOCAL_W-1 downto 0) := (others => '0');
    signal a_rd_col  : unsigned(LOCAL_W-1 downto 0) := (others => '0');
    signal a_rd_data : signed(DATA_WIDTH-1 downto 0);
    signal b_rd_row  : unsigned(LOCAL_W-1 downto 0) := (others => '0');
    signal b_rd_col  : unsigned(LOCAL_W-1 downto 0) := (others => '0');
    signal b_rd_data : signed(DATA_WIDTH-1 downto 0);
    signal compute_panel_idx : natural range 0 to PANEL_TILES-1 := 0;

    type tile_data_array_t is array (natural range <>) of signed(DATA_WIDTH-1 downto 0);
    type std_logic_array_t is array (natural range <>) of std_logic;

    signal a_rd_data_bank : tile_data_array_t(0 to PANEL_TILES-1);
    signal b_rd_data_bank : tile_data_array_t(0 to PANEL_TILES-1);
    signal a_wr_en_bank   : std_logic_array_t(0 to PANEL_TILES-1);
    signal b_wr_en_bank   : std_logic_array_t(0 to PANEL_TILES-1);

    signal pack_c_rd_row : unsigned(LOCAL_W-1 downto 0) := (others => '0');
    signal pack_c_rd_col : unsigned(LOCAL_W-1 downto 0) := (others => '0');
    signal writer_c_rd_row : unsigned(LOCAL_W-1 downto 0);
    signal writer_c_rd_col : unsigned(LOCAL_W-1 downto 0);
    signal c_rd_row_mux : unsigned(LOCAL_W-1 downto 0);
    signal c_rd_col_mux : unsigned(LOCAL_W-1 downto 0);
    signal c_rd_data : signed(ACC_WIDTH-1 downto 0);

    signal compute_c_wr_en   : std_logic := '0';
    signal compute_c_wr_row  : unsigned(LOCAL_W-1 downto 0) := (others => '0');
    signal compute_c_wr_col  : unsigned(LOCAL_W-1 downto 0) := (others => '0');
    signal compute_c_wr_data : signed(ACC_WIDTH-1 downto 0) := (others => '0');
    signal c_wr_en_mux   : std_logic;
    signal c_wr_row_mux  : unsigned(LOCAL_W-1 downto 0);
    signal c_wr_col_mux  : unsigned(LOCAL_W-1 downto 0);
    signal c_wr_data_mux : signed(ACC_WIDTH-1 downto 0);

    signal core_start : std_logic := '0';
    signal core_done  : std_logic;
    signal core_a_tile : std_logic_vector((TILE_ELEMS*DATA_WIDTH)-1 downto 0) := (others => '0');
    signal core_b_tile : std_logic_vector((TILE_ELEMS*DATA_WIDTH)-1 downto 0) := (others => '0');
    signal core_c_tile_in  : std_logic_vector((TILE_ELEMS*ACC_WIDTH)-1 downto 0) := (others => '0');
    signal core_c_tile_out : std_logic_vector((TILE_ELEMS*ACC_WIDTH)-1 downto 0);
    signal core_mac_ops_issued : unsigned(31 downto 0);

    function local_row(idx : natural) return natural is
    begin
        return idx / TILE_SIZE;
    end function;

    function local_col(idx : natural) return natural is
    begin
        return idx mod TILE_SIZE;
    end function;

begin

    assert N mod TILE_SIZE = 0
        report "matrix_mult_sdram_tiled_core exige N multiplo de TILE_SIZE."
        severity failure;

    assert DATA_WIDTH = 8 and ACC_WIDTH = 32 and SDRAM_DATA_W = 32
        report "matrix_mult_sdram_tiled_core basico assume A/B int8, C int32 e SDRAM 32 bits."
        severity failure;

    assert MEMORY_BANKS_A = MEMORY_BANKS_B
        report "matrix_mult_sdram_tiled_core exige MEMORY_BANKS_A = MEMORY_BANKS_B para panel buffering."
        severity failure;

    busy <= sched_busy;
    done <= sched_done;
    core_rst <= rst or soft_clear;
    data_out <= data_out_reg;
    rd_valid <= data_out_valid_reg;
    host_accept_ready <= '1' when host_pending = '0' and
                                  sched_busy = '0' and
                                  sdram_busy = '0' and
                                  sdram_cmd_ready = '1'
                         else '0';
    host_cmd_ready <= host_accept_ready;
    mac_ops_issued <= resize(core_mac_ops_issued, mac_ops_issued'length);
    memory_error <= sdram_error;
    a_rd_data <= a_rd_data_bank(compute_panel_idx);
    b_rd_data <= b_rd_data_bank(compute_panel_idx);

    c_rd_row_mux <= writer_c_rd_row when writer_busy = '1' else pack_c_rd_row;
    c_rd_col_mux <= writer_c_rd_col when writer_busy = '1' else pack_c_rd_col;

    c_wr_en_mux   <= compute_c_wr_en or loader_c_wr_en;
    c_wr_row_mux  <= compute_c_wr_row when compute_c_wr_en = '1' else loader_c_wr_row;
    c_wr_col_mux  <= compute_c_wr_col when compute_c_wr_en = '1' else loader_c_wr_col;
    c_wr_data_mux <= compute_c_wr_data when compute_c_wr_en = '1' else loader_c_wr_data;

    u_memory_manager : entity work.memory_manager
        generic map (
            ADDR_WIDTH => SDRAM_ADDR_W,
            DATA_WIDTH => SDRAM_DATA_W
        )
        port map (
            clk => clk,
            rst => core_rst,
            host_valid  => host_pending,
            host_write  => host_write_reg,
            host_addr   => host_addr_reg,
            host_wdata  => host_wdata_reg,
            host_be     => host_be_reg,
            host_ready  => host_ready,
            host_rvalid => host_rvalid,
            host_rdata  => host_rdata,
            loader_rd_req   => loader_rd_req,
            loader_rd_addr  => loader_rd_addr,
            loader_rd_ready => loader_rd_ready,
            loader_rd_valid => loader_rd_valid,
            loader_rd_data  => loader_rd_data,
            writer_wr_req   => writer_wr_req,
            writer_wr_addr  => writer_wr_addr,
            writer_wr_data  => writer_wr_data,
            writer_wr_be    => writer_wr_be,
            writer_wr_ready => writer_wr_ready,
            sdram_cmd_valid => sdram_cmd_valid,
            sdram_cmd_write => sdram_cmd_write,
            sdram_cmd_addr  => sdram_cmd_addr,
            sdram_cmd_wdata => sdram_cmd_wdata,
            sdram_cmd_be    => sdram_cmd_be,
            sdram_cmd_ready => sdram_cmd_ready,
            sdram_rd_valid  => sdram_rd_valid,
            sdram_rd_data   => sdram_rd_data
        );

    u_sdram : entity work.sdram_controller_wrapper
        generic map (
            ADDR_WIDTH     => SDRAM_ADDR_W,
            DATA_WIDTH     => SDRAM_DATA_W,
            EMULATED_WORDS => EMULATED_WORDS,
            SIMULATION_MODEL => SDRAM_SIMULATION_MODEL,
            READ_TIMEOUT_CYCLES => SDRAM_READ_TIMEOUT_CYCLES
        )
        port map (
            clk => clk,
            rst => rst,
            cmd_valid => sdram_cmd_valid,
            cmd_write => sdram_cmd_write,
            cmd_addr  => sdram_cmd_addr,
            cmd_wdata => sdram_cmd_wdata,
            cmd_be    => sdram_cmd_be,
            cmd_ready => sdram_cmd_ready,
            rd_valid  => sdram_rd_valid,
            rd_data   => sdram_rd_data,
            busy      => sdram_busy,
            error     => sdram_error,
            dram_addr  => dram_addr,
            dram_ba    => dram_ba,
            dram_cas_n => dram_cas_n,
            dram_cke   => dram_cke,
            dram_clk   => dram_clk,
            dram_cs_n  => dram_cs_n,
            dram_dq    => dram_dq,
            dram_ldqm  => dram_ldqm,
            dram_ras_n => dram_ras_n,
            dram_udqm  => dram_udqm,
            dram_we_n  => dram_we_n
        );

    u_scheduler : entity work.sdram_tile_scheduler
        generic map (
            N => N,
            TILE_SIZE => TILE_SIZE,
            PANEL_TILES => PANEL_TILES
        )
        port map (
            clk => clk,
            rst => core_rst,
            start => start,
            busy  => sched_busy,
            done  => sched_done,
            tile_i => sched_tile_i,
            tile_j => sched_tile_j,
            tile_k => sched_tile_k,
            panel_count => sched_panel_count,
            load_c => sched_load_c,
            loader_start  => sched_loader_start,
            loader_done   => sched_loader_done,
            compute_start => sched_compute_start,
            compute_done  => sched_compute_done,
            writer_start  => sched_writer_start,
            writer_done   => sched_writer_done,
            load_active    => load_active,
            compute_active => compute_active,
            store_active   => store_active,
            tile_done      => tile_done
        );

    u_loader : entity work.tile_loader
        generic map (
            N => N,
            TILE_SIZE => TILE_SIZE,
            PANEL_TILES => PANEL_TILES,
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH => ACC_WIDTH,
            SDRAM_ADDR_W => SDRAM_ADDR_W,
            SDRAM_DATA_W => SDRAM_DATA_W,
            ACCUMULATE_C => ACCUMULATE_C,
            BASE_A_BYTES => BASE_A_BYTES,
            BASE_B_BYTES => BASE_B_BYTES,
            BASE_C_BYTES => BASE_C_BYTES
        )
        port map (
            clk => clk,
            rst => core_rst,
            start => sched_loader_start,
            load_c => sched_load_c,
            tile_i => sched_tile_i,
            tile_j => sched_tile_j,
            tile_k => sched_tile_k,
            panel_count => sched_panel_count,
            busy => loader_busy,
            done => sched_loader_done,
            mem_rd_req => loader_rd_req,
            mem_rd_addr => loader_rd_addr,
            mem_rd_ready => loader_rd_ready,
            mem_rd_valid => loader_rd_valid,
            mem_rd_data => loader_rd_data,
            a_wr_en => loader_a_wr_en,
            a_wr_row => loader_a_wr_row,
            a_wr_col => loader_a_wr_col,
            a_wr_bank => loader_a_wr_bank,
            a_wr_data => loader_a_wr_data,
            b_wr_en => loader_b_wr_en,
            b_wr_row => loader_b_wr_row,
            b_wr_col => loader_b_wr_col,
            b_wr_bank => loader_b_wr_bank,
            b_wr_data => loader_b_wr_data,
            c_wr_en => loader_c_wr_en,
            c_wr_row => loader_c_wr_row,
            c_wr_col => loader_c_wr_col,
            c_wr_data => loader_c_wr_data
        );

    u_writer : entity work.tile_writer
        generic map (
            N => N,
            TILE_SIZE => TILE_SIZE,
            ACC_WIDTH => ACC_WIDTH,
            SDRAM_ADDR_W => SDRAM_ADDR_W,
            SDRAM_DATA_W => SDRAM_DATA_W,
            BASE_A_BYTES => BASE_A_BYTES,
            DATA_WIDTH => DATA_WIDTH,
            BASE_B_BYTES => BASE_B_BYTES,
            BASE_C_BYTES => BASE_C_BYTES
        )
        port map (
            clk => clk,
            rst => core_rst,
            start => sched_writer_start,
            tile_i => sched_tile_i,
            tile_j => sched_tile_j,
            busy => writer_busy,
            done => sched_writer_done,
            c_rd_row => writer_c_rd_row,
            c_rd_col => writer_c_rd_col,
            c_rd_data => c_rd_data,
            mem_wr_req => writer_wr_req,
            mem_wr_addr => writer_wr_addr,
            mem_wr_data => writer_wr_data,
            mem_wr_be => writer_wr_be,
            mem_wr_ready => writer_wr_ready
        );

    gen_panel_buffers : for bank_idx in 0 to PANEL_TILES-1 generate
    begin
        a_wr_en_bank(bank_idx) <= '1' when loader_a_wr_en = '1' and loader_a_wr_bank = bank_idx else '0';
        b_wr_en_bank(bank_idx) <= '1' when loader_b_wr_en = '1' and loader_b_wr_bank = bank_idx else '0';

        u_a_buffer : entity work.tile_buffer_m10k
            generic map (
                TILE_SIZE => TILE_SIZE,
                DATA_WIDTH => DATA_WIDTH
            )
            port map (
                clk => clk,
                wr_en => a_wr_en_bank(bank_idx),
                wr_row => loader_a_wr_row,
                wr_col => loader_a_wr_col,
                wr_data => loader_a_wr_data,
                rd_row => a_rd_row,
                rd_col => a_rd_col,
                rd_data => a_rd_data_bank(bank_idx)
            );

        u_b_buffer : entity work.tile_buffer_m10k
            generic map (
                TILE_SIZE => TILE_SIZE,
                DATA_WIDTH => DATA_WIDTH
            )
            port map (
                clk => clk,
                wr_en => b_wr_en_bank(bank_idx),
                wr_row => loader_b_wr_row,
                wr_col => loader_b_wr_col,
                wr_data => loader_b_wr_data,
                rd_row => b_rd_row,
                rd_col => b_rd_col,
                rd_data => b_rd_data_bank(bank_idx)
            );
    end generate gen_panel_buffers;

    u_c_buffer : entity work.tile_buffer_m10k
        generic map (
            TILE_SIZE => TILE_SIZE,
            DATA_WIDTH => ACC_WIDTH
        )
        port map (
            clk => clk,
            wr_en => c_wr_en_mux,
            wr_row => c_wr_row_mux,
            wr_col => c_wr_col_mux,
            wr_data => c_wr_data_mux,
            rd_row => c_rd_row_mux,
            rd_col => c_rd_col_mux,
            rd_data => c_rd_data
        );

    u_compute : entity work.matrix_tiled_compute_core
        generic map (
            TILE_SIZE => TILE_SIZE,
            NUM_MACS => NUM_MACS,
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH => ACC_WIDTH,
            MAC_PIPELINE_STAGES => MAC_PIPELINE_STAGES
        )
        port map (
            clk => clk,
            rst => core_rst,
            start => core_start,
            done => core_done,
            a_tile => core_a_tile,
            b_tile => core_b_tile,
            c_tile_in => core_c_tile_in,
            c_tile_out => core_c_tile_out,
            mac_ops_issued => core_mac_ops_issued
        );

    process(clk, core_rst)
    begin
        if core_rst = '1' then
            host_pending   <= '0';
            host_write_reg <= '0';
            host_addr_reg  <= (others => '0');
            host_wdata_reg <= (others => '0');
            host_be_reg    <= (others => '0');
            data_out_reg   <= (others => '0');
            data_out_valid_reg <= '0';

        elsif rising_edge(clk) then
            data_out_valid_reg <= '0';

            if host_pending = '1' and host_ready = '1' then
                host_pending <= '0';
            end if;

            if host_rvalid = '1' then
                data_out_reg <= signed(host_rdata(ACC_WIDTH-1 downto 0));
                data_out_valid_reg <= '1';
            end if;

            if host_cmd_valid = '1' and host_accept_ready = '1' then
                if host_cmd_write = '1' then
                    host_pending   <= '1';
                    host_write_reg <= '1';
                    host_addr_reg  <= matrix_linear_byte_addr(matrix_sel,
                                                              to_integer(cmd_addr),
                                                              N,
                                                              DATA_WIDTH,
                                                              ACC_WIDTH,
                                                              BASE_A_BYTES,
                                                              BASE_B_BYTES,
                                                              BASE_C_BYTES,
                                                              SDRAM_ADDR_W);
                    host_wdata_reg <= (others => '0');
                    host_wdata_reg(DATA_WIDTH-1 downto 0) <= std_logic_vector(data_in);
                    host_be_reg    <= (others => '0');
                    host_be_reg(0) <= '1';
                else
                    host_pending   <= '1';
                    host_write_reg <= '0';
                    host_addr_reg  <= matrix_linear_byte_addr(MATRIX_ID_C,
                                                              to_integer(cmd_addr),
                                                              N,
                                                              DATA_WIDTH,
                                                              ACC_WIDTH,
                                                              BASE_A_BYTES,
                                                              BASE_B_BYTES,
                                                              BASE_C_BYTES,
                                                              SDRAM_ADDR_W);
                    host_wdata_reg <= (others => '0');
                    host_be_reg    <= (others => '0');
                end if;
            end if;
        end if;
    end process;

    process(clk, core_rst)
        variable lr : natural;
        variable lc : natural;
        variable left_data : natural;
        variable left_acc  : natural;
    begin
        if core_rst = '1' then
            compute_state <= COMPUTE_IDLE;
            pack_idx <= 0;
            unpack_idx <= 0;
            compute_panel_idx <= 0;
            core_start <= '0';
            sched_compute_done <= '0';
            compute_c_wr_en <= '0';
            compute_c_wr_row <= (others => '0');
            compute_c_wr_col <= (others => '0');
            compute_c_wr_data <= (others => '0');
            a_rd_row <= (others => '0');
            a_rd_col <= (others => '0');
            b_rd_row <= (others => '0');
            b_rd_col <= (others => '0');
            pack_c_rd_row <= (others => '0');
            pack_c_rd_col <= (others => '0');
            core_a_tile <= (others => '0');
            core_b_tile <= (others => '0');
            core_c_tile_in <= (others => '0');

        elsif rising_edge(clk) then
            core_start <= '0';
            sched_compute_done <= '0';
            compute_c_wr_en <= '0';

            case compute_state is
                when COMPUTE_IDLE =>
                    if sched_compute_start = '1' then
                        pack_idx <= 0;
                        compute_panel_idx <= 0;
                        compute_state <= PACK_SETUP;
                    end if;

                when PACK_SETUP =>
                    lr := local_row(pack_idx);
                    lc := local_col(pack_idx);
                    a_rd_row <= to_unsigned(lr, LOCAL_W);
                    a_rd_col <= to_unsigned(lc, LOCAL_W);
                    b_rd_row <= to_unsigned(lr, LOCAL_W);
                    b_rd_col <= to_unsigned(lc, LOCAL_W);
                    pack_c_rd_row <= to_unsigned(lr, LOCAL_W);
                    pack_c_rd_col <= to_unsigned(lc, LOCAL_W);
                    compute_state <= PACK_WAIT;

                when PACK_WAIT =>
                    compute_state <= PACK_CAPTURE;

                when PACK_CAPTURE =>
                    left_data := ((pack_idx + 1) * DATA_WIDTH) - 1;
                    left_acc  := ((pack_idx + 1) * ACC_WIDTH) - 1;
                    core_a_tile(left_data downto left_data - DATA_WIDTH + 1) <= std_logic_vector(a_rd_data);
                    core_b_tile(left_data downto left_data - DATA_WIDTH + 1) <= std_logic_vector(b_rd_data);
                    core_c_tile_in(left_acc downto left_acc - ACC_WIDTH + 1) <= std_logic_vector(c_rd_data);

                    if pack_idx = TILE_ELEMS-1 then
                        compute_state <= START_CORE;
                    else
                        pack_idx <= pack_idx + 1;
                        compute_state <= PACK_SETUP;
                    end if;

                when START_CORE =>
                    core_start <= '1';
                    compute_state <= WAIT_CORE;

                when WAIT_CORE =>
                    if core_done = '1' then
                        unpack_idx <= 0;
                        compute_state <= UNPACK_WRITE;
                    end if;

                when UNPACK_WRITE =>
                    lr := local_row(unpack_idx);
                    lc := local_col(unpack_idx);
                    left_acc := ((unpack_idx + 1) * ACC_WIDTH) - 1;
                    compute_c_wr_en <= '1';
                    compute_c_wr_row <= to_unsigned(lr, LOCAL_W);
                    compute_c_wr_col <= to_unsigned(lc, LOCAL_W);
                    compute_c_wr_data <= signed(core_c_tile_out(left_acc downto left_acc - ACC_WIDTH + 1));

                    if unpack_idx = TILE_ELEMS-1 then
                        compute_state <= COMPUTE_DONE_STATE;
                    else
                        unpack_idx <= unpack_idx + 1;
                    end if;

                when COMPUTE_DONE_STATE =>
                    if compute_panel_idx + 1 < sched_panel_count then
                        compute_panel_idx <= compute_panel_idx + 1;
                        pack_idx <= 0;
                        compute_state <= PACK_SETUP;
                    else
                        sched_compute_done <= '1';
                        compute_state <= COMPUTE_IDLE;
                    end if;
            end case;
        end if;
    end process;

end architecture rtl;
