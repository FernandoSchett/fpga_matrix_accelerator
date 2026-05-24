library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;

entity tile_loader is
    generic (
        N                : positive := 128;
        TILE_SIZE        : positive := 4;
        DATA_WIDTH       : positive := 8;
        SDRAM_DATA_WIDTH : positive := 32;
        SDRAM_ADDR_WIDTH : positive := 18
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start  : in std_logic;
        tile_i : in unsigned(clog2((N / TILE_SIZE) + 1)-1 downto 0);
        tile_j : in unsigned(clog2((N / TILE_SIZE) + 1)-1 downto 0);
        tile_k : in unsigned(clog2((N / TILE_SIZE) + 1)-1 downto 0);

        busy : out std_logic;
        done : out std_logic;

        sdram_rd_req   : out std_logic;
        sdram_rd_addr  : out unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
        sdram_rd_data  : in std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
        sdram_rd_valid : in std_logic;
        sdram_rd_ready : in std_logic;
        sdram_busy     : in std_logic;

        tile_a_wr_en    : out std_logic;
        tile_a_local_row : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        tile_a_local_col : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        tile_a_wr_data   : out signed(DATA_WIDTH-1 downto 0);

        tile_b_wr_en    : out std_logic;
        tile_b_local_row : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        tile_b_local_col : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        tile_b_wr_data   : out signed(DATA_WIDTH-1 downto 0)
    );
end entity tile_loader;

architecture rtl of tile_loader is

    constant TILE_ELEMS : positive := TILE_SIZE * TILE_SIZE;
    constant BASE_A     : natural := 0;
    constant BASE_B     : natural := N * N;

    type state_t is (
        IDLE,
        ISSUE_A_READ,
        WAIT_A_READ,
        WRITE_A,
        ISSUE_B_READ,
        WAIT_B_READ,
        WRITE_B,
        DONE_STATE
    );

    signal state : state_t := IDLE;
    signal idx   : integer range 0 to TILE_ELEMS-1 := 0;

    signal busy_reg : std_logic := '0';
    signal done_reg : std_logic := '0';

    signal sdram_rd_req_reg  : std_logic := '0';
    signal sdram_rd_addr_reg : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');

    signal tile_a_wr_en_reg  : std_logic := '0';
    signal tile_b_wr_en_reg  : std_logic := '0';
    signal tile_a_data_reg   : signed(DATA_WIDTH-1 downto 0) := (others => '0');
    signal tile_b_data_reg   : signed(DATA_WIDTH-1 downto 0) := (others => '0');

    signal local_row_reg : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');
    signal local_col_reg : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');

    function matrix_addr(
        constant base    : natural;
        constant row_idx : natural;
        constant col_idx : natural
    ) return unsigned is
    begin
        return to_unsigned(base + (row_idx * N) + col_idx, SDRAM_ADDR_WIDTH);
    end function;

begin

    assert N mod TILE_SIZE = 0
        report "tile_loader exige N multiplo de TILE_SIZE."
        severity failure;

    assert SDRAM_DATA_WIDTH >= DATA_WIDTH
        report "tile_loader exige SDRAM_DATA_WIDTH >= DATA_WIDTH."
        severity failure;

    busy <= busy_reg;
    done <= done_reg;

    sdram_rd_req  <= sdram_rd_req_reg;
    sdram_rd_addr <= sdram_rd_addr_reg;

    tile_a_wr_en    <= tile_a_wr_en_reg;
    tile_a_local_row <= local_row_reg;
    tile_a_local_col <= local_col_reg;
    tile_a_wr_data   <= tile_a_data_reg;

    tile_b_wr_en    <= tile_b_wr_en_reg;
    tile_b_local_row <= local_row_reg;
    tile_b_local_col <= local_col_reg;
    tile_b_wr_data   <= tile_b_data_reg;

    process(clk, rst)
        variable local_row  : natural;
        variable local_col  : natural;
        variable global_row : natural;
        variable global_col : natural;
    begin
        if rst = '1' then
            state             <= IDLE;
            idx               <= 0;
            busy_reg          <= '0';
            done_reg          <= '0';
            sdram_rd_req_reg  <= '0';
            sdram_rd_addr_reg <= (others => '0');
            tile_a_wr_en_reg  <= '0';
            tile_b_wr_en_reg  <= '0';
            tile_a_data_reg   <= (others => '0');
            tile_b_data_reg   <= (others => '0');
            local_row_reg     <= (others => '0');
            local_col_reg     <= (others => '0');

        elsif rising_edge(clk) then
            sdram_rd_req_reg <= '0';
            tile_a_wr_en_reg <= '0';
            tile_b_wr_en_reg <= '0';

            local_row := idx / TILE_SIZE;
            local_col := idx mod TILE_SIZE;

            local_row_reg <= to_unsigned(local_row, local_row_reg'length);
            local_col_reg <= to_unsigned(local_col, local_col_reg'length);

            case state is
                when IDLE =>
                    busy_reg <= '0';
                    done_reg <= '0';

                    if start = '1' then
                        idx      <= 0;
                        busy_reg <= '1';
                        state    <= ISSUE_A_READ;
                    end if;

                when ISSUE_A_READ =>
                    global_row := to_integer(tile_i) * TILE_SIZE + local_row;
                    global_col := to_integer(tile_k) * TILE_SIZE + local_col;

                    sdram_rd_addr_reg <= matrix_addr(BASE_A, global_row, global_col);

                    if sdram_rd_ready = '1' then
                        sdram_rd_req_reg <= '1';
                        state            <= WAIT_A_READ;
                    end if;

                when WAIT_A_READ =>
                    if sdram_rd_valid = '1' then
                        tile_a_data_reg <= signed(sdram_rd_data(DATA_WIDTH-1 downto 0));
                        state           <= WRITE_A;
                    end if;

                when WRITE_A =>
                    tile_a_wr_en_reg <= '1';
                    state            <= ISSUE_B_READ;

                when ISSUE_B_READ =>
                    global_row := to_integer(tile_k) * TILE_SIZE + local_row;
                    global_col := to_integer(tile_j) * TILE_SIZE + local_col;

                    sdram_rd_addr_reg <= matrix_addr(BASE_B, global_row, global_col);

                    if sdram_rd_ready = '1' then
                        sdram_rd_req_reg <= '1';
                        state            <= WAIT_B_READ;
                    end if;

                when WAIT_B_READ =>
                    if sdram_rd_valid = '1' then
                        tile_b_data_reg <= signed(sdram_rd_data(DATA_WIDTH-1 downto 0));
                        state           <= WRITE_B;
                    end if;

                when WRITE_B =>
                    tile_b_wr_en_reg <= '1';

                    if idx = TILE_ELEMS-1 then
                        state <= DONE_STATE;
                    else
                        idx   <= idx + 1;
                        state <= ISSUE_A_READ;
                    end if;

                when DONE_STATE =>
                    busy_reg <= '0';
                    done_reg <= '1';

                    if start = '0' then
                        state <= IDLE;
                    end if;
            end case;
        end if;
    end process;

end architecture rtl;
