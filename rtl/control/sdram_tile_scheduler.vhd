library ieee;
use ieee.std_logic_1164.all;

entity sdram_tile_scheduler is
    generic (
        N         : positive := 512;
        TILE_SIZE : positive := 16
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start : in std_logic;
        busy  : out std_logic;
        done  : out std_logic;

        tile_i : out natural range 0 to (N/TILE_SIZE)-1;
        tile_j : out natural range 0 to (N/TILE_SIZE)-1;
        tile_k : out natural range 0 to (N/TILE_SIZE)-1;

        load_c        : out std_logic;
        loader_start  : out std_logic;
        loader_done   : in std_logic;
        compute_start : out std_logic;
        compute_done  : in std_logic;
        writer_start  : out std_logic;
        writer_done   : in std_logic;

        load_active    : out std_logic;
        compute_active : out std_logic;
        store_active   : out std_logic;
        tile_done      : out std_logic
    );
end entity sdram_tile_scheduler;

architecture rtl of sdram_tile_scheduler is

    constant NUM_TILES : positive := N / TILE_SIZE;

    type state_t is (
        IDLE,
        START_LOAD,
        WAIT_LOAD,
        START_COMPUTE,
        WAIT_COMPUTE,
        NEXT_K,
        START_WRITE,
        WAIT_WRITE,
        NEXT_TILE,
        DONE_STATE
    );

    signal state      : state_t := IDLE;
    signal tile_i_reg : natural range 0 to NUM_TILES-1 := 0;
    signal tile_j_reg : natural range 0 to NUM_TILES-1 := 0;
    signal tile_k_reg : natural range 0 to NUM_TILES-1 := 0;

begin

    assert N mod TILE_SIZE = 0
        report "sdram_tile_scheduler exige N multiplo de TILE_SIZE."
        severity failure;

    tile_i <= tile_i_reg;
    tile_j <= tile_j_reg;
    tile_k <= tile_k_reg;

    load_c <= '1' when tile_k_reg = 0 else '0';

    load_active    <= '1' when state = START_LOAD or state = WAIT_LOAD else '0';
    compute_active <= '1' when state = START_COMPUTE or state = WAIT_COMPUTE else '0';
    store_active   <= '1' when state = START_WRITE or state = WAIT_WRITE else '0';

    process(clk, rst)
    begin
        if rst = '1' then
            state         <= IDLE;
            tile_i_reg    <= 0;
            tile_j_reg    <= 0;
            tile_k_reg    <= 0;
            busy          <= '0';
            done          <= '0';
            tile_done     <= '0';
            loader_start  <= '0';
            compute_start <= '0';
            writer_start  <= '0';

        elsif rising_edge(clk) then
            done          <= '0';
            tile_done     <= '0';
            loader_start  <= '0';
            compute_start <= '0';
            writer_start  <= '0';

            case state is
                when IDLE =>
                    busy <= '0';
                    if start = '1' then
                        busy       <= '1';
                        tile_i_reg <= 0;
                        tile_j_reg <= 0;
                        tile_k_reg <= 0;
                        state      <= START_LOAD;
                    end if;

                when START_LOAD =>
                    busy         <= '1';
                    loader_start <= '1';
                    state        <= WAIT_LOAD;

                when WAIT_LOAD =>
                    busy <= '1';
                    if loader_done = '1' then
                        state <= START_COMPUTE;
                    end if;

                when START_COMPUTE =>
                    busy          <= '1';
                    compute_start <= '1';
                    state         <= WAIT_COMPUTE;

                when WAIT_COMPUTE =>
                    busy <= '1';
                    if compute_done = '1' then
                        state <= NEXT_K;
                    end if;

                when NEXT_K =>
                    busy <= '1';
                    if tile_k_reg = NUM_TILES-1 then
                        state <= START_WRITE;
                    else
                        tile_k_reg <= tile_k_reg + 1;
                        state      <= START_LOAD;
                    end if;

                when START_WRITE =>
                    busy         <= '1';
                    writer_start <= '1';
                    state        <= WAIT_WRITE;

                when WAIT_WRITE =>
                    busy <= '1';
                    if writer_done = '1' then
                        tile_done <= '1';
                        state     <= NEXT_TILE;
                    end if;

                when NEXT_TILE =>
                    busy       <= '1';
                    tile_k_reg <= 0;
                    if tile_j_reg = NUM_TILES-1 then
                        tile_j_reg <= 0;
                        if tile_i_reg = NUM_TILES-1 then
                            state <= DONE_STATE;
                        else
                            tile_i_reg <= tile_i_reg + 1;
                            state      <= START_LOAD;
                        end if;
                    else
                        tile_j_reg <= tile_j_reg + 1;
                        state      <= START_LOAD;
                    end if;

                when DONE_STATE =>
                    busy  <= '0';
                    done  <= '1';
                    state <= IDLE;
            end case;
        end if;
    end process;

end architecture rtl;
