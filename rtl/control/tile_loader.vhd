library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;
use work.sdram_bus_if_pkg.all;
use work.matrix_memory_map_pkg.all;

entity tile_loader is
    generic (
        N              : positive := 512;
        TILE_SIZE      : positive := 16;
        PANEL_TILES    : positive := 1;
        DATA_WIDTH     : positive := 8;
        ACC_WIDTH      : positive := 32;
        SDRAM_ADDR_W   : positive := 25;
        SDRAM_DATA_W   : positive := 32;
        ACCUMULATE_C   : boolean := false;
        BASE_A_BYTES   : natural := 0;
        BASE_B_BYTES   : natural := 0;
        BASE_C_BYTES   : natural := 0
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start  : in std_logic;
        load_c : in std_logic;
        tile_i : in natural range 0 to (N/TILE_SIZE)-1;
        tile_j : in natural range 0 to (N/TILE_SIZE)-1;
        tile_k : in natural range 0 to (N/TILE_SIZE)-1;
        panel_count : in natural range 1 to PANEL_TILES;
        bank_base : in natural range 0 to PANEL_TILES-1;
        busy   : out std_logic;
        done   : out std_logic;

        mem_rd_req   : out std_logic;
        mem_rd_addr  : out unsigned(SDRAM_ADDR_W-1 downto 0);
        mem_rd_ready : in std_logic;
        mem_rd_valid : in std_logic;
        mem_rd_data  : in std_logic_vector(SDRAM_DATA_W-1 downto 0);

        a_wr_en   : out std_logic;
        a_wr_row  : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        a_wr_col  : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        a_wr_bank : out natural range 0 to PANEL_TILES-1;
        a_wr_data : out signed(DATA_WIDTH-1 downto 0);

        b_wr_en   : out std_logic;
        b_wr_row  : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        b_wr_col  : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        b_wr_bank : out natural range 0 to PANEL_TILES-1;
        b_wr_data : out signed(DATA_WIDTH-1 downto 0);

        c_wr_en   : out std_logic;
        c_wr_row  : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        c_wr_col  : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        c_wr_data : out signed(ACC_WIDTH-1 downto 0)
    );
end entity tile_loader;

architecture rtl of tile_loader is

    type state_t is (
        IDLE,
        REQ_A_WORD,
        WAIT_A_WORD,
        UNPACK_A_WORD,
        REQ_B_WORD,
        WAIT_B_WORD,
        UNPACK_B_WORD,
        INIT_C_ZERO,
        REQ_C,
        WAIT_C,
        DONE_STATE
    );

    constant LOCAL_W       : positive := clog2(TILE_SIZE);
    constant TILE_ELEMS    : positive := TILE_SIZE * TILE_SIZE;
    constant DATA_PER_WORD : positive := SDRAM_DATA_W / DATA_WIDTH;

    signal state    : state_t := IDLE;
    signal elem_idx : natural range 0 to TILE_ELEMS-1 := 0;
    signal panel_idx : natural range 0 to PANEL_TILES-1 := 0;
    signal burst_row : natural range 0 to TILE_SIZE-1 := 0;
    signal burst_col : natural range 0 to TILE_SIZE-1 := 0;
    signal burst_word : std_logic_vector(SDRAM_DATA_W-1 downto 0) := (others => '0');
    signal burst_lane_base : natural range 0 to DATA_PER_WORD-1 := 0;
    signal burst_count : natural range 1 to DATA_PER_WORD := 1;
    signal burst_offset : natural range 0 to DATA_PER_WORD-1 := 0;

    function local_row(idx : natural) return natural is
    begin
        return idx / TILE_SIZE;
    end function;

    function local_col(idx : natural) return natural is
    begin
        return idx mod TILE_SIZE;
    end function;

    function min_nat(left_value : natural; right_value : natural) return natural is
    begin
        if left_value < right_value then
            return left_value;
        end if;
        return right_value;
    end function;

begin

    assert SDRAM_DATA_W >= ACC_WIDTH
        report "tile_loader exige SDRAM_DATA_W >= ACC_WIDTH nesta versao simples."
        severity failure;

    assert SDRAM_DATA_W mod DATA_WIDTH = 0
        report "tile_loader exige SDRAM_DATA_W multiplo de DATA_WIDTH para desempacotar bursts."
        severity failure;

    assert N mod DATA_PER_WORD = 0
        report "tile_loader burst exige N multiplo dos elementos por word SDRAM."
        severity failure;

    process(clk, rst)
        variable lr : natural;
        variable lc : natural;
        variable global_row : natural;
        variable global_col : natural;
        variable aligned_col : natural;
        variable lane : natural;
        variable count_value : natural;
        variable left_bit : natural;
        variable next_col : natural;
        variable active_bank : natural;
    begin
        if rst = '1' then
            state       <= IDLE;
            elem_idx    <= 0;
            panel_idx   <= 0;
            burst_row   <= 0;
            burst_col   <= 0;
            burst_word  <= (others => '0');
            burst_lane_base <= 0;
            burst_count <= 1;
            burst_offset <= 0;
            mem_rd_req  <= '0';
            mem_rd_addr <= (others => '0');
            a_wr_en     <= '0';
            a_wr_row    <= (others => '0');
            a_wr_col    <= (others => '0');
            a_wr_bank   <= 0;
            a_wr_data   <= (others => '0');
            b_wr_en     <= '0';
            b_wr_row    <= (others => '0');
            b_wr_col    <= (others => '0');
            b_wr_bank   <= 0;
            b_wr_data   <= (others => '0');
            c_wr_en     <= '0';
            c_wr_row    <= (others => '0');
            c_wr_col    <= (others => '0');
            c_wr_data   <= (others => '0');
            done        <= '0';
            busy        <= '0';

        elsif rising_edge(clk) then
            mem_rd_req <= '0';
            a_wr_en    <= '0';
            b_wr_en    <= '0';
            c_wr_en    <= '0';
            done       <= '0';

            lr := local_row(elem_idx);
            lc := local_col(elem_idx);

            case state is
                when IDLE =>
                    busy <= '0';
                    if start = '1' then
                        busy     <= '1';
                        elem_idx <= 0;
                        panel_idx <= 0;
                        burst_row <= 0;
                        burst_col <= 0;
                        burst_offset <= 0;
                        state    <= REQ_A_WORD;
                    end if;

                when REQ_A_WORD =>
                    busy        <= '1';
                    global_row := tile_i * TILE_SIZE + burst_row;
                    global_col := (tile_k + panel_idx) * TILE_SIZE + burst_col;
                    aligned_col := (global_col / DATA_PER_WORD) * DATA_PER_WORD;
                    lane := global_col mod DATA_PER_WORD;
                    count_value := min_nat(DATA_PER_WORD - lane, TILE_SIZE - burst_col);

                    mem_rd_req  <= '1';
                    mem_rd_addr <= matrix_byte_addr(MATRIX_SEL_A,
                                                    global_row,
                                                    aligned_col,
                                                    N,
                                                    DATA_WIDTH,
                                                    ACC_WIDTH,
                                                    BASE_A_BYTES,
                                                    BASE_B_BYTES,
                                                    BASE_C_BYTES,
                                                    SDRAM_ADDR_W);
                    if mem_rd_ready = '1' then
                        burst_lane_base <= lane;
                        burst_count <= count_value;
                        burst_offset <= 0;
                        state <= WAIT_A_WORD;
                    end if;

                when WAIT_A_WORD =>
                    busy <= '1';
                    if mem_rd_valid = '1' then
                        burst_word <= mem_rd_data;
                        state <= UNPACK_A_WORD;
                    end if;

                when UNPACK_A_WORD =>
                    busy <= '1';
                    active_bank := (bank_base + panel_idx) mod PANEL_TILES;
                    lane := burst_lane_base + burst_offset;
                    left_bit := ((lane + 1) * DATA_WIDTH) - 1;

                    a_wr_en   <= '1';
                    a_wr_row  <= to_unsigned(burst_row, LOCAL_W);
                    a_wr_col  <= to_unsigned(burst_col + burst_offset, LOCAL_W);
                    a_wr_bank <= active_bank;
                    a_wr_data <= signed(burst_word(left_bit downto left_bit - DATA_WIDTH + 1));

                    if burst_offset = burst_count-1 then
                        burst_offset <= 0;
                        next_col := burst_col + burst_count;
                        if next_col >= TILE_SIZE then
                            burst_col <= 0;
                            if burst_row = TILE_SIZE-1 then
                                burst_row <= 0;
                                state <= REQ_B_WORD;
                            else
                                burst_row <= burst_row + 1;
                                state <= REQ_A_WORD;
                            end if;
                        else
                            burst_col <= next_col;
                            state <= REQ_A_WORD;
                        end if;
                    else
                        burst_offset <= burst_offset + 1;
                    end if;

                when REQ_B_WORD =>
                    busy        <= '1';
                    global_row := (tile_k + panel_idx) * TILE_SIZE + burst_row;
                    global_col := tile_j * TILE_SIZE + burst_col;
                    aligned_col := (global_col / DATA_PER_WORD) * DATA_PER_WORD;
                    lane := global_col mod DATA_PER_WORD;
                    count_value := min_nat(DATA_PER_WORD - lane, TILE_SIZE - burst_col);

                    mem_rd_req  <= '1';
                    mem_rd_addr <= matrix_byte_addr(MATRIX_SEL_B,
                                                    global_row,
                                                    aligned_col,
                                                    N,
                                                    DATA_WIDTH,
                                                    ACC_WIDTH,
                                                    BASE_A_BYTES,
                                                    BASE_B_BYTES,
                                                    BASE_C_BYTES,
                                                    SDRAM_ADDR_W);
                    if mem_rd_ready = '1' then
                        burst_lane_base <= lane;
                        burst_count <= count_value;
                        burst_offset <= 0;
                        state <= WAIT_B_WORD;
                    end if;

                when WAIT_B_WORD =>
                    busy <= '1';
                    if mem_rd_valid = '1' then
                        burst_word <= mem_rd_data;
                        state <= UNPACK_B_WORD;
                    end if;

                when UNPACK_B_WORD =>
                    busy <= '1';
                    active_bank := (bank_base + panel_idx) mod PANEL_TILES;
                    lane := burst_lane_base + burst_offset;
                    left_bit := ((lane + 1) * DATA_WIDTH) - 1;

                    b_wr_en   <= '1';
                    b_wr_row  <= to_unsigned(burst_row, LOCAL_W);
                    b_wr_col  <= to_unsigned(burst_col + burst_offset, LOCAL_W);
                    b_wr_bank <= active_bank;
                    b_wr_data <= signed(burst_word(left_bit downto left_bit - DATA_WIDTH + 1));

                    if burst_offset = burst_count-1 then
                        burst_offset <= 0;
                        next_col := burst_col + burst_count;
                        if next_col >= TILE_SIZE then
                            burst_col <= 0;
                            if burst_row = TILE_SIZE-1 then
                                burst_row <= 0;
                                if panel_idx = panel_count-1 then
                                    elem_idx <= 0;
                                    if load_c = '1' then
                                        if ACCUMULATE_C then
                                            state <= REQ_C;
                                        else
                                            state <= INIT_C_ZERO;
                                        end if;
                                    else
                                        state <= DONE_STATE;
                                    end if;
                                else
                                    panel_idx <= panel_idx + 1;
                                    state <= REQ_A_WORD;
                                end if;
                            else
                                burst_row <= burst_row + 1;
                                state <= REQ_B_WORD;
                            end if;
                        else
                            burst_col <= next_col;
                            state <= REQ_B_WORD;
                        end if;
                    else
                        burst_offset <= burst_offset + 1;
                    end if;

                -- Legacy single-byte states replaced by row-word unpacking above.
                -- C remains 32-bit per element, so it still uses one read per C entry.
                when INIT_C_ZERO =>
                    busy      <= '1';
                    c_wr_en   <= '1';
                    c_wr_row  <= to_unsigned(lr, LOCAL_W);
                    c_wr_col  <= to_unsigned(lc, LOCAL_W);
                    c_wr_data <= (others => '0');
                    if elem_idx = TILE_ELEMS-1 then
                        state <= DONE_STATE;
                    else
                        elem_idx <= elem_idx + 1;
                        state    <= INIT_C_ZERO;
                    end if;

                when REQ_C =>
                    busy        <= '1';
                    mem_rd_req  <= '1';
                    mem_rd_addr <= matrix_byte_addr(MATRIX_SEL_C,
                                                    tile_i * TILE_SIZE + lr,
                                                    tile_j * TILE_SIZE + lc,
                                                    N,
                                                    DATA_WIDTH,
                                                    ACC_WIDTH,
                                                    BASE_A_BYTES,
                                                    BASE_B_BYTES,
                                                    BASE_C_BYTES,
                                                    SDRAM_ADDR_W);
                    if mem_rd_ready = '1' then
                        state <= WAIT_C;
                    end if;

                when WAIT_C =>
                    busy <= '1';
                    if mem_rd_valid = '1' then
                        c_wr_en   <= '1';
                        c_wr_row  <= to_unsigned(lr, LOCAL_W);
                        c_wr_col  <= to_unsigned(lc, LOCAL_W);
                        c_wr_data <= signed(mem_rd_data(ACC_WIDTH-1 downto 0));
                        if elem_idx = TILE_ELEMS-1 then
                            state <= DONE_STATE;
                        else
                            elem_idx <= elem_idx + 1;
                            state    <= REQ_C;
                        end if;
                    end if;

                when DONE_STATE =>
                    busy  <= '0';
                    done  <= '1';
                    state <= IDLE;
            end case;
        end if;
    end process;

end architecture rtl;
