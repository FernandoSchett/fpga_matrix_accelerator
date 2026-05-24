library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;

entity tile_store is
    generic (
        TILE_SIZE        : positive := 4;
        ELEMENT_WIDTH    : positive := 32;
        SDRAM_DATA_WIDTH : positive := 32;
        SDRAM_ADDR_WIDTH : positive := 18
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start      : in std_logic;
        base_addr  : in unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
        row_stride : in unsigned(SDRAM_ADDR_WIDTH-1 downto 0);

        busy : out std_logic;
        done : out std_logic;

        sdram_req     : out std_logic;
        sdram_we      : out std_logic;
        sdram_addr    : out unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
        sdram_wdata   : out std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
        sdram_byte_en : out std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0);
        sdram_ready   : in std_logic;

        tile_rd_addr : out unsigned(clog2((TILE_SIZE*TILE_SIZE) + 1)-1 downto 0);
        tile_rd_data : in signed(ELEMENT_WIDTH-1 downto 0)
    );
end entity tile_store;

architecture rtl of tile_store is

    constant TILE_ELEMS : positive := TILE_SIZE * TILE_SIZE;

    type state_t is (
        IDLE,
        SET_TILE_ADDR,
        WAIT_TILE,
        ISSUE_WRITE,
        DONE_STATE
    );

    signal state : state_t := IDLE;
    signal idx   : integer range 0 to TILE_ELEMS-1 := 0;

    signal busy_reg : std_logic := '0';
    signal done_reg : std_logic := '0';

    signal sdram_req_reg   : std_logic := '0';
    signal sdram_addr_reg  : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal sdram_wdata_reg : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0) := (others => '0');

    signal tile_rd_addr_reg : unsigned(clog2(TILE_ELEMS + 1)-1 downto 0) := (others => '0');

begin

    assert SDRAM_DATA_WIDTH >= ELEMENT_WIDTH
        report "tile_store exige SDRAM_DATA_WIDTH >= ELEMENT_WIDTH."
        severity failure;

    busy <= busy_reg;
    done <= done_reg;

    sdram_req     <= sdram_req_reg;
    sdram_we      <= '1';
    sdram_addr    <= sdram_addr_reg;
    sdram_wdata   <= sdram_wdata_reg;
    sdram_byte_en <= (others => '1');

    tile_rd_addr <= tile_rd_addr_reg;

    process(clk, rst)
        variable row_idx  : natural;
        variable col_idx  : natural;
        variable addr_nat : natural;
    begin
        if rst = '1' then
            state            <= IDLE;
            idx              <= 0;
            busy_reg         <= '0';
            done_reg         <= '0';
            sdram_req_reg    <= '0';
            sdram_addr_reg   <= (others => '0');
            sdram_wdata_reg  <= (others => '0');
            tile_rd_addr_reg <= (others => '0');

        elsif rising_edge(clk) then
            sdram_req_reg <= '0';

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
                    tile_rd_addr_reg <= to_unsigned(idx, tile_rd_addr_reg'length);
                    state <= WAIT_TILE;

                when WAIT_TILE =>
                    state <= ISSUE_WRITE;

                when ISSUE_WRITE =>
                    row_idx := idx / TILE_SIZE;
                    col_idx := idx mod TILE_SIZE;
                    addr_nat := to_integer(base_addr) + (row_idx * to_integer(row_stride)) + col_idx;

                    sdram_addr_reg  <= to_unsigned(addr_nat, SDRAM_ADDR_WIDTH);
                    sdram_wdata_reg <= std_logic_vector(resize(tile_rd_data, SDRAM_DATA_WIDTH));

                    if sdram_ready = '1' then
                        sdram_req_reg <= '1';

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
