library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;

entity tile_store is
    generic (
        N                : positive := 128;
        TILE_SIZE        : positive := 4;
        ACC_WIDTH        : positive := 32;
        SDRAM_DATA_WIDTH : positive := 32;
        SDRAM_ADDR_WIDTH : positive := 18
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start  : in std_logic;
        tile_i : in unsigned(clog2((N / TILE_SIZE) + 1)-1 downto 0);
        tile_j : in unsigned(clog2((N / TILE_SIZE) + 1)-1 downto 0);

        busy : out std_logic;
        done : out std_logic;

        sdram_wr_req   : out std_logic;
        sdram_wr_addr  : out unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
        sdram_wr_data  : out std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
        sdram_wr_ready : in std_logic;
        sdram_busy     : in std_logic;

        tile_c_local_row : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        tile_c_local_col : out unsigned(clog2(TILE_SIZE)-1 downto 0);
        tile_c_rd_data   : in signed(ACC_WIDTH-1 downto 0)
    );
end entity tile_store;

architecture rtl of tile_store is

    constant TILE_ELEMS : positive := TILE_SIZE * TILE_SIZE;

    type state_t is (
        IDLE,
        SET_TILE_ADDR,
        WAIT_TILE,
        ISSUE_WRITE,
        WAIT_WRITE_ACCEPT,
        WAIT_WRITE_DONE,
        DONE_STATE
    );

    signal state : state_t := IDLE;
    signal idx   : integer range 0 to TILE_ELEMS-1 := 0;

    signal busy_reg : std_logic := '0';
    signal done_reg : std_logic := '0';

    signal sdram_wr_req_reg  : std_logic := '0';
    signal sdram_wr_addr_reg : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal sdram_wr_data_reg : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0) := (others => '0');

    signal local_row_reg : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');
    signal local_col_reg : unsigned(clog2(TILE_SIZE)-1 downto 0) := (others => '0');

    function matrix_addr(
        constant row_idx : natural;
        constant col_idx : natural
    ) return unsigned is
    begin
        return to_unsigned((row_idx * N) + col_idx, SDRAM_ADDR_WIDTH);
    end function;

begin

    assert N mod TILE_SIZE = 0
        report "tile_store exige N multiplo de TILE_SIZE."
        severity failure;

    assert SDRAM_DATA_WIDTH >= ACC_WIDTH
        report "tile_store exige SDRAM_DATA_WIDTH >= ACC_WIDTH."
        severity failure;

    busy <= busy_reg;
    done <= done_reg;

    sdram_wr_req  <= sdram_wr_req_reg;
    sdram_wr_addr <= sdram_wr_addr_reg;
    sdram_wr_data <= sdram_wr_data_reg;

    tile_c_local_row <= local_row_reg;
    tile_c_local_col <= local_col_reg;

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
            sdram_wr_req_reg  <= '0';
            sdram_wr_addr_reg <= (others => '0');
            sdram_wr_data_reg <= (others => '0');
            local_row_reg     <= (others => '0');
            local_col_reg     <= (others => '0');

        elsif rising_edge(clk) then
            sdram_wr_req_reg <= '0';

            case state is
                when IDLE =>
                    busy_reg <= '0';
                    done_reg <= '0';

                    if start = '1' then
                        idx      <= 0;
                        busy_reg <= '1';
                        state    <= SET_TILE_ADDR;
                    end if;

                when SET_TILE_ADDR =>
                    local_row := idx / TILE_SIZE;
                    local_col := idx mod TILE_SIZE;

                    local_row_reg <= to_unsigned(local_row, local_row_reg'length);
                    local_col_reg <= to_unsigned(local_col, local_col_reg'length);
                    state         <= WAIT_TILE;

                when WAIT_TILE =>
                    state <= ISSUE_WRITE;

                when ISSUE_WRITE =>
                    local_row  := idx / TILE_SIZE;
                    local_col  := idx mod TILE_SIZE;
                    global_row := to_integer(tile_i) * TILE_SIZE + local_row;
                    global_col := to_integer(tile_j) * TILE_SIZE + local_col;

                    sdram_wr_addr_reg <= matrix_addr(global_row, global_col);
                    sdram_wr_data_reg <= std_logic_vector(resize(tile_c_rd_data, SDRAM_DATA_WIDTH));

                    if sdram_wr_ready = '1' and sdram_busy = '0' then
                        sdram_wr_req_reg <= '1';
                        state            <= WAIT_WRITE_ACCEPT;
                    end if;

                when WAIT_WRITE_ACCEPT =>
                    state <= WAIT_WRITE_DONE;

                when WAIT_WRITE_DONE =>
                    if sdram_wr_ready = '1' and sdram_busy = '0' then
                        if idx = TILE_ELEMS-1 then
                            state <= DONE_STATE;
                        else
                            idx   <= idx + 1;
                            state <= SET_TILE_ADDR;
                        end if;
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
