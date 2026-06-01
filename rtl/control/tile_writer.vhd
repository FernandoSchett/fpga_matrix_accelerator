library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;

entity tile_writer is
    generic (
        N              : positive := 512;
        TILE_SIZE      : positive := 16;
        ACC_WIDTH      : positive := 32;
        SDRAM_ADDR_W   : positive := 25;
        SDRAM_DATA_W   : positive := 32;
        BASE_A_BYTES   : natural := 0;
        DATA_WIDTH     : positive := 8;
        BASE_B_BYTES   : natural := 0;
        BASE_C_BYTES   : natural := 0
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start  : in std_logic;
        tile_i : in natural range 0 to (N/TILE_SIZE)-1;
        tile_j : in natural range 0 to (N/TILE_SIZE)-1;
        busy   : out std_logic;
        done   : out std_logic;

        c_rd_row  : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        c_rd_col  : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        c_rd_data : in signed(ACC_WIDTH-1 downto 0);

        mem_wr_req   : out std_logic;
        mem_wr_addr  : out unsigned(SDRAM_ADDR_W-1 downto 0);
        mem_wr_data  : out std_logic_vector(SDRAM_DATA_W-1 downto 0);
        mem_wr_be    : out std_logic_vector((SDRAM_DATA_W/8)-1 downto 0);
        mem_wr_ready : in std_logic
    );
end entity tile_writer;

architecture rtl of tile_writer is

    type state_t is (IDLE, SETUP_READ, WAIT_READ, ISSUE_WRITE, DONE_STATE);

    function select_base(configured_base : natural; default_base : natural) return natural is
    begin
        if configured_base = 0 then
            return default_base;
        end if;
        return configured_base;
    end function;

    constant LOCAL_W        : positive := clog2(TILE_SIZE);
    constant TILE_ELEMS     : positive := TILE_SIZE * TILE_SIZE;
    constant DATA_BYTES     : positive := (DATA_WIDTH + 7) / 8;
    constant ACC_BYTES      : positive := (ACC_WIDTH + 7) / 8;
    constant MATRIX_ELEMS   : natural := N * N;
    constant A_BYTES        : natural := MATRIX_ELEMS * DATA_BYTES;
    constant B_BYTES        : natural := MATRIX_ELEMS * DATA_BYTES;
    constant DEFAULT_BASE_B : natural := BASE_A_BYTES + A_BYTES;
    constant SELECT_BASE_B  : natural := select_base(BASE_B_BYTES, DEFAULT_BASE_B);
    constant DEFAULT_BASE_C : natural := SELECT_BASE_B + B_BYTES;
    constant SELECT_BASE_C  : natural := select_base(BASE_C_BYTES, DEFAULT_BASE_C);

    signal state    : state_t := IDLE;
    signal elem_idx : natural range 0 to TILE_ELEMS-1 := 0;

    function local_row(idx : natural) return natural is
    begin
        return idx / TILE_SIZE;
    end function;

    function local_col(idx : natural) return natural is
    begin
        return idx mod TILE_SIZE;
    end function;

    function c_byte_addr(row_value : natural; col_value : natural) return unsigned is
        variable linear_index : natural;
    begin
        linear_index := row_value * N + col_value;
        return to_unsigned(SELECT_BASE_C + (linear_index * ACC_BYTES), SDRAM_ADDR_W);
    end function;

begin

    assert SDRAM_DATA_W >= ACC_WIDTH
        report "tile_writer exige SDRAM_DATA_W >= ACC_WIDTH nesta versao simples."
        severity failure;

    process(clk, rst)
        variable lr : natural;
        variable lc : natural;
    begin
        if rst = '1' then
            state       <= IDLE;
            elem_idx    <= 0;
            busy        <= '0';
            done        <= '0';
            mem_wr_req  <= '0';
            mem_wr_addr <= (others => '0');
            mem_wr_data <= (others => '0');
            mem_wr_be   <= (others => '0');
            c_rd_row    <= (others => '0');
            c_rd_col    <= (others => '0');

        elsif rising_edge(clk) then
            mem_wr_req <= '0';
            done       <= '0';

            lr := local_row(elem_idx);
            lc := local_col(elem_idx);

            case state is
                when IDLE =>
                    busy <= '0';
                    if start = '1' then
                        busy     <= '1';
                        elem_idx <= 0;
                        state    <= SETUP_READ;
                    end if;

                when SETUP_READ =>
                    busy     <= '1';
                    c_rd_row <= to_unsigned(lr, LOCAL_W);
                    c_rd_col <= to_unsigned(lc, LOCAL_W);
                    state    <= WAIT_READ;

                when WAIT_READ =>
                    busy  <= '1';
                    state <= ISSUE_WRITE;

                when ISSUE_WRITE =>
                    busy        <= '1';
                    mem_wr_req  <= '1';
                    mem_wr_addr <= c_byte_addr(tile_i * TILE_SIZE + lr,
                                               tile_j * TILE_SIZE + lc);
                    mem_wr_data <= std_logic_vector(resize(c_rd_data, SDRAM_DATA_W));
                    mem_wr_be   <= (others => '1');
                    if mem_wr_ready = '1' then
                        if elem_idx = TILE_ELEMS-1 then
                            state <= DONE_STATE;
                        else
                            elem_idx <= elem_idx + 1;
                            state    <= SETUP_READ;
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
