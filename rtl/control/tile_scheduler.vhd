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

        start : in std_logic;

        load_done    : in std_logic;
        compute_done : in std_logic;
        store_done   : in std_logic;

        busy : out std_logic;
        done : out std_logic;

        init_c_tile  : out std_logic;
        load_start   : out std_logic;
        compute_start : out std_logic;
        store_start  : out std_logic;

        tile_i : out unsigned(clog2((N / TILE_SIZE) + 1)-1 downto 0);
        tile_j : out unsigned(clog2((N / TILE_SIZE) + 1)-1 downto 0);
        tile_k : out unsigned(clog2((N / TILE_SIZE) + 1)-1 downto 0)
    );
end entity tile_scheduler;

architecture rtl of tile_scheduler is

    constant NUM_TILES : positive := N / TILE_SIZE;
    constant IDX_WIDTH : positive := clog2(NUM_TILES + 1);

    type state_t is (
        ST_IDLE,
        ST_INIT_C_TILE,
        ST_START_LOAD,
        ST_WAIT_LOAD,
        ST_START_COMPUTE,
        ST_WAIT_COMPUTE,
        ST_NEXT_K,
        ST_START_STORE,
        ST_WAIT_STORE,
        ST_NEXT_J,
        ST_NEXT_I,
        ST_DONE
    );

    signal state : state_t := ST_IDLE;

    signal i_reg : integer range 0 to NUM_TILES-1 := 0;
    signal j_reg : integer range 0 to NUM_TILES-1 := 0;
    signal k_reg : integer range 0 to NUM_TILES-1 := 0;

    signal busy_reg : std_logic := '0';
    signal done_reg : std_logic := '0';

    signal init_c_tile_reg  : std_logic := '0';
    signal load_start_reg   : std_logic := '0';
    signal compute_start_reg : std_logic := '0';
    signal store_start_reg  : std_logic := '0';

begin

    assert N mod TILE_SIZE = 0
        report "tile_scheduler exige N multiplo de TILE_SIZE."
        severity failure;

    busy <= busy_reg;
    done <= done_reg;

    init_c_tile  <= init_c_tile_reg;
    load_start   <= load_start_reg;
    compute_start <= compute_start_reg;
    store_start  <= store_start_reg;

    tile_i <= resize(to_unsigned(i_reg, IDX_WIDTH), tile_i'length);
    tile_j <= resize(to_unsigned(j_reg, IDX_WIDTH), tile_j'length);
    tile_k <= resize(to_unsigned(k_reg, IDX_WIDTH), tile_k'length);

    process(clk, rst)
    begin
        if rst = '1' then
            state             <= ST_IDLE;
            i_reg             <= 0;
            j_reg             <= 0;
            k_reg             <= 0;
            busy_reg          <= '0';
            done_reg          <= '0';
            init_c_tile_reg   <= '0';
            load_start_reg    <= '0';
            compute_start_reg <= '0';
            store_start_reg   <= '0';

        elsif rising_edge(clk) then
            init_c_tile_reg   <= '0';
            load_start_reg    <= '0';
            compute_start_reg <= '0';
            store_start_reg   <= '0';

            case state is
                when ST_IDLE =>
                    busy_reg <= '0';
                    done_reg <= '0';

                    if start = '1' then
                        i_reg    <= 0;
                        j_reg    <= 0;
                        k_reg    <= 0;
                        busy_reg <= '1';
                        state    <= ST_INIT_C_TILE;
                    end if;

                when ST_INIT_C_TILE =>
                    busy_reg        <= '1';
                    done_reg        <= '0';
                    init_c_tile_reg <= '1';
                    k_reg           <= 0;
                    state           <= ST_START_LOAD;

                when ST_START_LOAD =>
                    load_start_reg <= '1';
                    state          <= ST_WAIT_LOAD;

                when ST_WAIT_LOAD =>
                    if load_done = '1' then
                        state <= ST_START_COMPUTE;
                    end if;

                when ST_START_COMPUTE =>
                    compute_start_reg <= '1';
                    state             <= ST_WAIT_COMPUTE;

                when ST_WAIT_COMPUTE =>
                    if compute_done = '1' then
                        state <= ST_NEXT_K;
                    end if;

                when ST_NEXT_K =>
                    if k_reg = NUM_TILES-1 then
                        k_reg <= 0;
                        state <= ST_START_STORE;
                    else
                        k_reg <= k_reg + 1;
                        state <= ST_START_LOAD;
                    end if;

                when ST_START_STORE =>
                    store_start_reg <= '1';
                    state           <= ST_WAIT_STORE;

                when ST_WAIT_STORE =>
                    if store_done = '1' then
                        state <= ST_NEXT_J;
                    end if;

                when ST_NEXT_J =>
                    k_reg <= 0;

                    if j_reg = NUM_TILES-1 then
                        j_reg <= 0;
                        state <= ST_NEXT_I;
                    else
                        j_reg <= j_reg + 1;
                        state <= ST_INIT_C_TILE;
                    end if;

                when ST_NEXT_I =>
                    k_reg <= 0;

                    if i_reg = NUM_TILES-1 then
                        state <= ST_DONE;
                    else
                        i_reg <= i_reg + 1;
                        state <= ST_INIT_C_TILE;
                    end if;

                when ST_DONE =>
                    busy_reg <= '0';
                    done_reg <= '1';

                    if start = '0' then
                        state <= ST_IDLE;
                    end if;
            end case;
        end if;
    end process;

end architecture rtl;
