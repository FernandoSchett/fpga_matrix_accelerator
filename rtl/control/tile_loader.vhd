library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;

entity tile_loader is
    generic (
        TILE_SIZE        : positive := 4;
        ELEMENT_WIDTH    : positive := 8;
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
        sdram_rvalid  : in std_logic;
        sdram_rdata   : in std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

        tile_wr_en   : out std_logic;
        tile_wr_addr : out unsigned(clog2((TILE_SIZE*TILE_SIZE) + 1)-1 downto 0);
        tile_wr_data : out signed(ELEMENT_WIDTH-1 downto 0)
    );
end entity tile_loader;

architecture rtl of tile_loader is

    constant TILE_ELEMS : positive := TILE_SIZE * TILE_SIZE;

    type state_t is (
        IDLE,
        ISSUE_READ,
        WAIT_READ,
        WRITE_TILE,
        DONE_STATE
    );

    signal state : state_t := IDLE;
    signal idx   : integer range 0 to TILE_ELEMS-1 := 0;

    signal busy_reg : std_logic := '0';
    signal done_reg : std_logic := '0';

    signal sdram_req_reg  : std_logic := '0';
    signal sdram_addr_reg : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');

    signal tile_wr_en_reg   : std_logic := '0';
    signal tile_wr_addr_reg : unsigned(clog2(TILE_ELEMS + 1)-1 downto 0) := (others => '0');
    signal tile_wr_data_reg : signed(ELEMENT_WIDTH-1 downto 0) := (others => '0');

begin

    busy <= busy_reg;
    done <= done_reg;

    sdram_req     <= sdram_req_reg;
    sdram_we      <= '0';
    sdram_addr    <= sdram_addr_reg;
    sdram_wdata   <= (others => '0');
    sdram_byte_en <= (others => '1');

    tile_wr_en   <= tile_wr_en_reg;
    tile_wr_addr <= tile_wr_addr_reg;
    tile_wr_data <= tile_wr_data_reg;

    process(clk, rst)
        variable row_idx  : natural;
        variable col_idx  : natural;
        variable addr_nat : natural;
    begin
        if rst = '1' then
            state             <= IDLE;
            idx               <= 0;
            busy_reg          <= '0';
            done_reg          <= '0';
            sdram_req_reg     <= '0';
            sdram_addr_reg    <= (others => '0');
            tile_wr_en_reg    <= '0';
            tile_wr_addr_reg  <= (others => '0');
            tile_wr_data_reg  <= (others => '0');

        elsif rising_edge(clk) then
            sdram_req_reg  <= '0';
            tile_wr_en_reg <= '0';

            case state is
                when IDLE =>
                    busy_reg <= '0';
                    done_reg <= '0';

                    if start = '1' then
                        idx      <= 0;
                        busy_reg <= '1';
                        state    <= ISSUE_READ;
                    end if;

                when ISSUE_READ =>
                    row_idx := idx / TILE_SIZE;
                    col_idx := idx mod TILE_SIZE;
                    addr_nat := to_integer(base_addr) + (row_idx * to_integer(row_stride)) + col_idx;

                    sdram_addr_reg <= to_unsigned(addr_nat, SDRAM_ADDR_WIDTH);

                    if sdram_ready = '1' then
                        sdram_req_reg <= '1';
                        state         <= WAIT_READ;
                    end if;

                when WAIT_READ =>
                    if sdram_rvalid = '1' then
                        tile_wr_data_reg <= signed(sdram_rdata(ELEMENT_WIDTH-1 downto 0));
                        state            <= WRITE_TILE;
                    end if;

                when WRITE_TILE =>
                    tile_wr_addr_reg <= to_unsigned(idx, tile_wr_addr_reg'length);
                    tile_wr_en_reg   <= '1';

                    if idx = TILE_ELEMS-1 then
                        state <= DONE_STATE;
                    else
                        idx   <= idx + 1;
                        state <= ISSUE_READ;
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
