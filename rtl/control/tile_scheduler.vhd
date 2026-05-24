library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;

entity tile_scheduler is
    generic (
        N         : positive := 128;
        TILE_SIZE : positive := 4
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start   : in std_logic;
        advance : in std_logic;

        busy    : out std_logic;
        valid   : out std_logic;
        done    : out std_logic;
        first_k : out std_logic;

        tile_row : out unsigned(clog2((N / TILE_SIZE) + 1)-1 downto 0);
        tile_col : out unsigned(clog2((N / TILE_SIZE) + 1)-1 downto 0);
        tile_k   : out unsigned(clog2((N / TILE_SIZE) + 1)-1 downto 0)
    );
end entity tile_scheduler;

architecture rtl of tile_scheduler is

    constant NUM_TILES : positive := N / TILE_SIZE;
    constant IDX_WIDTH : positive := clog2(NUM_TILES + 1);

    type state_t is (
        IDLE,
        RUN,
        DONE_STATE
    );

    signal state : state_t := IDLE;

    signal row_reg : integer range 0 to NUM_TILES-1 := 0;
    signal col_reg : integer range 0 to NUM_TILES-1 := 0;
    signal k_reg   : integer range 0 to NUM_TILES-1 := 0;

    signal busy_reg  : std_logic := '0';
    signal valid_reg : std_logic := '0';
    signal done_reg  : std_logic := '0';

begin

    assert N mod TILE_SIZE = 0
        report "tile_scheduler exige N multiplo de TILE_SIZE."
        severity failure;

    busy    <= busy_reg;
    valid   <= valid_reg;
    done    <= done_reg;
    first_k <= '1' when k_reg = 0 and valid_reg = '1' else '0';

    tile_row <= resize(to_unsigned(row_reg, IDX_WIDTH), tile_row'length);
    tile_col <= resize(to_unsigned(col_reg, IDX_WIDTH), tile_col'length);
    tile_k   <= resize(to_unsigned(k_reg, IDX_WIDTH), tile_k'length);

    process(clk, rst)
    begin
        if rst = '1' then
            state     <= IDLE;
            row_reg   <= 0;
            col_reg   <= 0;
            k_reg     <= 0;
            busy_reg  <= '0';
            valid_reg <= '0';
            done_reg  <= '0';

        elsif rising_edge(clk) then
            case state is
                when IDLE =>
                    busy_reg  <= '0';
                    valid_reg <= '0';
                    done_reg  <= '0';

                    if start = '1' then
                        row_reg   <= 0;
                        col_reg   <= 0;
                        k_reg     <= 0;
                        busy_reg  <= '1';
                        valid_reg <= '1';
                        state     <= RUN;
                    end if;

                when RUN =>
                    busy_reg  <= '1';
                    valid_reg <= '1';
                    done_reg  <= '0';

                    if advance = '1' then
                        if k_reg = NUM_TILES-1 then
                            k_reg <= 0;

                            if col_reg = NUM_TILES-1 then
                                col_reg <= 0;

                                if row_reg = NUM_TILES-1 then
                                    valid_reg <= '0';
                                    state     <= DONE_STATE;
                                else
                                    row_reg <= row_reg + 1;
                                end if;
                            else
                                col_reg <= col_reg + 1;
                            end if;
                        else
                            k_reg <= k_reg + 1;
                        end if;
                    end if;

                when DONE_STATE =>
                    busy_reg  <= '0';
                    valid_reg <= '0';
                    done_reg  <= '1';

                    if start = '0' then
                        state <= IDLE;
                    end if;
            end case;
        end if;
    end process;

end architecture rtl;
