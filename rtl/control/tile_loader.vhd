library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;
use work.sdram_bus_if_pkg.all;

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

    type state_t is (IDLE, REQ_A, WAIT_A, REQ_B, WAIT_B, INIT_C_ZERO, REQ_C, WAIT_C, DONE_STATE);

    function select_base(configured_base : natural; default_base : natural) return natural is
    begin
        if configured_base = 0 then
            return default_base;
        end if;
        return configured_base;
    end function;

    constant LOCAL_W       : positive := clog2(TILE_SIZE);
    constant TILE_ELEMS    : positive := TILE_SIZE * TILE_SIZE;
    constant DATA_BYTES    : positive := (DATA_WIDTH + 7) / 8;
    constant ACC_BYTES     : positive := (ACC_WIDTH + 7) / 8;
    constant MATRIX_ELEMS  : natural := N * N;
    constant A_BYTES       : natural := MATRIX_ELEMS * DATA_BYTES;
    constant B_BYTES       : natural := MATRIX_ELEMS * DATA_BYTES;
    constant DEFAULT_BASE_B : natural := BASE_A_BYTES + A_BYTES;
    constant SELECT_BASE_B  : natural := select_base(BASE_B_BYTES, DEFAULT_BASE_B);
    constant DEFAULT_BASE_C : natural := SELECT_BASE_B + B_BYTES;
    constant SELECT_BASE_C  : natural := select_base(BASE_C_BYTES, DEFAULT_BASE_C);

    signal state    : state_t := IDLE;
    signal elem_idx : natural range 0 to TILE_ELEMS-1 := 0;
    signal panel_idx : natural range 0 to PANEL_TILES-1 := 0;

    function local_row(idx : natural) return natural is
    begin
        return idx / TILE_SIZE;
    end function;

    function local_col(idx : natural) return natural is
    begin
        return idx mod TILE_SIZE;
    end function;

    function byte_addr(base_value : natural; row_value : natural; col_value : natural; elem_bytes : positive) return unsigned is
        variable linear_index : natural;
    begin
        linear_index := row_value * N + col_value;
        return to_unsigned(base_value + (linear_index * elem_bytes), SDRAM_ADDR_W);
    end function;

begin

    assert SDRAM_DATA_W >= ACC_WIDTH
        report "tile_loader exige SDRAM_DATA_W >= ACC_WIDTH nesta versao simples."
        severity failure;

    process(clk, rst)
        variable lr : natural;
        variable lc : natural;
    begin
        if rst = '1' then
            state       <= IDLE;
            elem_idx    <= 0;
            panel_idx   <= 0;
            mem_rd_req  <= '0';
            mem_rd_addr <= (others => '0');
            a_wr_en     <= '0';
            a_wr_bank   <= 0;
            b_wr_en     <= '0';
            b_wr_bank   <= 0;
            c_wr_en     <= '0';
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
                        state    <= REQ_A;
                    end if;

                when REQ_A =>
                    busy        <= '1';
                    mem_rd_req  <= '1';
                    mem_rd_addr <= byte_addr(BASE_A_BYTES,
                                             tile_i * TILE_SIZE + lr,
                                             (tile_k + panel_idx) * TILE_SIZE + lc,
                                             DATA_BYTES);
                    if mem_rd_ready = '1' then
                        state <= WAIT_A;
                    end if;

                when WAIT_A =>
                    busy <= '1';
                    if mem_rd_valid = '1' then
                        a_wr_en   <= '1';
                        a_wr_row  <= to_unsigned(lr, LOCAL_W);
                        a_wr_col  <= to_unsigned(lc, LOCAL_W);
                        a_wr_bank <= panel_idx;
                        a_wr_data <= signed(mem_rd_data(DATA_WIDTH-1 downto 0));
                        state     <= REQ_B;
                    end if;

                when REQ_B =>
                    busy        <= '1';
                    mem_rd_req  <= '1';
                    mem_rd_addr <= byte_addr(SELECT_BASE_B,
                                             (tile_k + panel_idx) * TILE_SIZE + lr,
                                             tile_j * TILE_SIZE + lc,
                                             DATA_BYTES);
                    if mem_rd_ready = '1' then
                        state <= WAIT_B;
                    end if;

                when WAIT_B =>
                    busy <= '1';
                    if mem_rd_valid = '1' then
                        b_wr_en   <= '1';
                        b_wr_row  <= to_unsigned(lr, LOCAL_W);
                        b_wr_col  <= to_unsigned(lc, LOCAL_W);
                        b_wr_bank <= panel_idx;
                        b_wr_data <= signed(mem_rd_data(DATA_WIDTH-1 downto 0));
                        if elem_idx = TILE_ELEMS-1 then
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
                                elem_idx  <= 0;
                                state     <= REQ_A;
                            end if;
                        else
                            elem_idx <= elem_idx + 1;
                            state    <= REQ_A;
                        end if;
                    end if;

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
                    mem_rd_addr <= byte_addr(SELECT_BASE_C,
                                             tile_i * TILE_SIZE + lr,
                                             tile_j * TILE_SIZE + lc,
                                             ACC_BYTES);
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
