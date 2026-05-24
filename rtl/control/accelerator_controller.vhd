library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;
use work.matrix_accel_config_pkg.all;

entity accelerator_controller is
    generic (
        N                : positive := DEFAULT_N;
        TILE_SIZE        : positive := DEFAULT_TILE_SIZE;
        NUM_MACS         : positive := DEFAULT_NUM_MACS;
        DATA_WIDTH       : positive := DEFAULT_DATA_WIDTH;
        ACC_WIDTH        : positive := DEFAULT_ACC_WIDTH;
        SDRAM_DATA_WIDTH : positive := DEFAULT_SDRAM_DATA_WIDTH;
        SDRAM_ADDR_WIDTH : positive := DEFAULT_SDRAM_ADDR_WIDTH
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        start : in std_logic;
        busy  : out std_logic;
        done  : out std_logic;

        sdram_req     : out std_logic;
        sdram_we      : out std_logic;
        sdram_addr    : out unsigned(SDRAM_ADDR_WIDTH-1 downto 0);
        sdram_wdata   : out std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);
        sdram_byte_en : out std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0);
        sdram_ready   : in std_logic;
        sdram_rvalid  : in std_logic;
        sdram_rdata   : in std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0);

        event_sdram_read  : out std_logic;
        event_sdram_write : out std_logic;
        event_mac_group   : out std_logic
    );
end entity accelerator_controller;

architecture rtl of accelerator_controller is

    constant MATRIX_ELEMS : positive := N * N;
    constant TILE_ELEMS   : positive := TILE_SIZE * TILE_SIZE;
    constant NUM_TILES    : positive := N / TILE_SIZE;

    constant A_BASE : natural := 0;
    constant B_BASE : natural := MATRIX_ELEMS;
    constant C_BASE : natural := MATRIX_ELEMS * 2;

    subtype data_t is signed(DATA_WIDTH-1 downto 0);
    subtype acc_t  is signed(ACC_WIDTH-1 downto 0);

    type data_tile_t is array (0 to TILE_ELEMS-1) of data_t;
    type acc_tile_t is array (0 to TILE_ELEMS-1) of acc_t;

    type state_t is (
        IDLE,
        CLEAR_C_TILE,
        LOAD_C_REQ,
        LOAD_C_WAIT,
        LOAD_A_REQ,
        LOAD_A_WAIT,
        LOAD_B_REQ,
        LOAD_B_WAIT,
        START_CORE,
        WAIT_CORE,
        CAPTURE_CORE,
        STORE_C_REQ,
        ADVANCE_TILE,
        DONE_STATE
    );

    signal state : state_t := IDLE;

    signal tile_row : integer range 0 to NUM_TILES-1 := 0;
    signal tile_col : integer range 0 to NUM_TILES-1 := 0;
    signal tile_k   : integer range 0 to NUM_TILES-1 := 0;
    signal tile_idx : integer range 0 to TILE_ELEMS-1 := 0;

    signal a_tile : data_tile_t := (others => (others => '0'));
    signal b_tile : data_tile_t := (others => (others => '0'));
    signal c_tile : acc_tile_t  := (others => (others => '0'));

    signal busy_reg : std_logic := '0';
    signal done_reg : std_logic := '0';

    signal sdram_req_reg     : std_logic := '0';
    signal sdram_we_reg      : std_logic := '0';
    signal sdram_addr_reg    : unsigned(SDRAM_ADDR_WIDTH-1 downto 0) := (others => '0');
    signal sdram_wdata_reg   : std_logic_vector(SDRAM_DATA_WIDTH-1 downto 0) := (others => '0');
    signal sdram_byte_en_reg : std_logic_vector((SDRAM_DATA_WIDTH/8)-1 downto 0) := (others => '1');

    signal event_read_reg      : std_logic := '0';
    signal event_write_reg     : std_logic := '0';
    signal event_mac_group_reg : std_logic := '0';

    signal core_start : std_logic := '0';
    signal core_done  : std_logic;

    signal core_a_tile     : std_logic_vector((TILE_ELEMS*DATA_WIDTH)-1 downto 0);
    signal core_b_tile     : std_logic_vector((TILE_ELEMS*DATA_WIDTH)-1 downto 0);
    signal core_c_tile_in  : std_logic_vector((TILE_ELEMS*ACC_WIDTH)-1 downto 0);
    signal core_c_tile_out : std_logic_vector((TILE_ELEMS*ACC_WIDTH)-1 downto 0);

    function matrix_addr(
        constant base    : natural;
        constant row_idx : natural;
        constant col_idx : natural
    ) return unsigned is
    begin
        return to_unsigned(base + row_major_addr(row_idx, col_idx, N), SDRAM_ADDR_WIDTH);
    end function;

    function tile_row_of(constant idx : natural) return natural is
    begin
        return idx / TILE_SIZE;
    end function;

    function tile_col_of(constant idx : natural) return natural is
    begin
        return idx mod TILE_SIZE;
    end function;

    function pack_data_tile(constant tile : data_tile_t) return std_logic_vector is
        variable result : std_logic_vector((TILE_ELEMS*DATA_WIDTH)-1 downto 0);
        variable left_i : natural;
    begin
        for idx in 0 to TILE_ELEMS-1 loop
            left_i := ((idx + 1) * DATA_WIDTH) - 1;
            result(left_i downto left_i - DATA_WIDTH + 1) := std_logic_vector(tile(idx));
        end loop;

        return result;
    end function;

    function pack_acc_tile(constant tile : acc_tile_t) return std_logic_vector is
        variable result : std_logic_vector((TILE_ELEMS*ACC_WIDTH)-1 downto 0);
        variable left_i : natural;
    begin
        for idx in 0 to TILE_ELEMS-1 loop
            left_i := ((idx + 1) * ACC_WIDTH) - 1;
            result(left_i downto left_i - ACC_WIDTH + 1) := std_logic_vector(tile(idx));
        end loop;

        return result;
    end function;

    function get_acc_from_flat(
        constant flat : std_logic_vector;
        constant idx  : natural
    ) return acc_t is
        variable result : acc_t;
        variable left_i : natural;
    begin
        left_i := ((idx + 1) * ACC_WIDTH) - 1;
        result := signed(flat(left_i downto left_i - ACC_WIDTH + 1));
        return result;
    end function;

begin

    assert N mod TILE_SIZE = 0
        report "accelerator_controller exige N multiplo de TILE_SIZE."
        severity failure;

    assert SDRAM_DATA_WIDTH >= ACC_WIDTH
        report "accelerator_controller exige SDRAM_DATA_WIDTH >= ACC_WIDTH."
        severity failure;

    busy <= busy_reg;
    done <= done_reg;

    sdram_req     <= sdram_req_reg;
    sdram_we      <= sdram_we_reg;
    sdram_addr    <= sdram_addr_reg;
    sdram_wdata   <= sdram_wdata_reg;
    sdram_byte_en <= sdram_byte_en_reg;

    event_sdram_read  <= event_read_reg;
    event_sdram_write <= event_write_reg;
    event_mac_group   <= event_mac_group_reg;

    core_a_tile    <= pack_data_tile(a_tile);
    core_b_tile    <= pack_data_tile(b_tile);
    core_c_tile_in <= pack_acc_tile(c_tile);

    u_compute : entity work.matrix_tiled_compute_core
        generic map (
            TILE_SIZE  => TILE_SIZE,
            NUM_MACS   => NUM_MACS,
            DATA_WIDTH => DATA_WIDTH,
            ACC_WIDTH  => ACC_WIDTH
        )
        port map (
            clk        => clk,
            rst        => rst,
            start      => core_start,
            done       => core_done,
            a_tile     => core_a_tile,
            b_tile     => core_b_tile,
            c_tile_in  => core_c_tile_in,
            c_tile_out => core_c_tile_out
        );

    process(clk, rst)
        variable local_row : natural;
        variable local_col : natural;
    begin
        if rst = '1' then
            state                 <= IDLE;
            tile_row              <= 0;
            tile_col              <= 0;
            tile_k                <= 0;
            tile_idx              <= 0;
            a_tile                <= (others => (others => '0'));
            b_tile                <= (others => (others => '0'));
            c_tile                <= (others => (others => '0'));
            busy_reg              <= '0';
            done_reg              <= '0';
            core_start            <= '0';
            sdram_req_reg         <= '0';
            sdram_we_reg          <= '0';
            sdram_addr_reg        <= (others => '0');
            sdram_wdata_reg       <= (others => '0');
            sdram_byte_en_reg     <= (others => '1');
            event_read_reg        <= '0';
            event_write_reg       <= '0';
            event_mac_group_reg   <= '0';

        elsif rising_edge(clk) then
            core_start          <= '0';
            sdram_req_reg       <= '0';
            sdram_we_reg        <= '0';
            sdram_byte_en_reg   <= (others => '1');
            event_read_reg      <= '0';
            event_write_reg     <= '0';
            event_mac_group_reg <= '0';

            case state is
                when IDLE =>
                    busy_reg <= '0';
                    done_reg <= '0';

                    if start = '1' then
                        tile_row <= 0;
                        tile_col <= 0;
                        tile_k   <= 0;
                        tile_idx <= 0;
                        busy_reg <= '1';
                        state    <= CLEAR_C_TILE;
                    end if;

                when CLEAR_C_TILE =>
                    c_tile   <= (others => (others => '0'));
                    tile_idx <= 0;
                    state    <= LOAD_A_REQ;

                when LOAD_C_REQ =>
                    local_row := tile_row_of(tile_idx);
                    local_col := tile_col_of(tile_idx);

                    sdram_addr_reg <= matrix_addr(C_BASE,
                                                  tile_row * TILE_SIZE + local_row,
                                                  tile_col * TILE_SIZE + local_col);

                    if sdram_ready = '1' then
                        sdram_req_reg  <= '1';
                        event_read_reg <= '1';
                        state          <= LOAD_C_WAIT;
                    end if;

                when LOAD_C_WAIT =>
                    if sdram_rvalid = '1' then
                        c_tile(tile_idx) <= signed(sdram_rdata(ACC_WIDTH-1 downto 0));

                        if tile_idx = TILE_ELEMS-1 then
                            tile_idx <= 0;
                            state    <= LOAD_A_REQ;
                        else
                            tile_idx <= tile_idx + 1;
                            state    <= LOAD_C_REQ;
                        end if;
                    end if;

                when LOAD_A_REQ =>
                    local_row := tile_row_of(tile_idx);
                    local_col := tile_col_of(tile_idx);

                    sdram_addr_reg <= matrix_addr(A_BASE,
                                                  tile_row * TILE_SIZE + local_row,
                                                  tile_k * TILE_SIZE + local_col);

                    if sdram_ready = '1' then
                        sdram_req_reg  <= '1';
                        event_read_reg <= '1';
                        state          <= LOAD_A_WAIT;
                    end if;

                when LOAD_A_WAIT =>
                    if sdram_rvalid = '1' then
                        a_tile(tile_idx) <= signed(sdram_rdata(DATA_WIDTH-1 downto 0));
                        state <= LOAD_B_REQ;
                    end if;

                when LOAD_B_REQ =>
                    local_row := tile_row_of(tile_idx);
                    local_col := tile_col_of(tile_idx);

                    sdram_addr_reg <= matrix_addr(B_BASE,
                                                  tile_k * TILE_SIZE + local_row,
                                                  tile_col * TILE_SIZE + local_col);

                    if sdram_ready = '1' then
                        sdram_req_reg  <= '1';
                        event_read_reg <= '1';
                        state          <= LOAD_B_WAIT;
                    end if;

                when LOAD_B_WAIT =>
                    if sdram_rvalid = '1' then
                        b_tile(tile_idx) <= signed(sdram_rdata(DATA_WIDTH-1 downto 0));

                        if tile_idx = TILE_ELEMS-1 then
                            tile_idx <= 0;
                            state    <= START_CORE;
                        else
                            tile_idx <= tile_idx + 1;
                            state    <= LOAD_A_REQ;
                        end if;
                    end if;

                when START_CORE =>
                    core_start          <= '1';
                    event_mac_group_reg <= '1';
                    state               <= WAIT_CORE;

                when WAIT_CORE =>
                    if core_done = '1' then
                        tile_idx <= 0;
                        state    <= CAPTURE_CORE;
                    end if;

                when CAPTURE_CORE =>
                    for idx in 0 to TILE_ELEMS-1 loop
                        c_tile(idx) <= get_acc_from_flat(core_c_tile_out, idx);
                    end loop;

                    tile_idx <= 0;
                    state    <= STORE_C_REQ;

                when STORE_C_REQ =>
                    local_row := tile_row_of(tile_idx);
                    local_col := tile_col_of(tile_idx);

                    sdram_addr_reg  <= matrix_addr(C_BASE,
                                                   tile_row * TILE_SIZE + local_row,
                                                   tile_col * TILE_SIZE + local_col);
                    sdram_wdata_reg <= std_logic_vector(resize(c_tile(tile_idx), SDRAM_DATA_WIDTH));
                    sdram_we_reg    <= '1';

                    if sdram_ready = '1' then
                        sdram_req_reg   <= '1';
                        event_write_reg <= '1';

                        if tile_idx = TILE_ELEMS-1 then
                            tile_idx <= 0;
                            state    <= ADVANCE_TILE;
                        else
                            tile_idx <= tile_idx + 1;
                        end if;
                    end if;

                when ADVANCE_TILE =>
                    if tile_k = NUM_TILES-1 then
                        tile_k <= 0;

                        if tile_col = NUM_TILES-1 then
                            tile_col <= 0;

                            if tile_row = NUM_TILES-1 then
                                state <= DONE_STATE;
                            else
                                tile_row <= tile_row + 1;
                                state    <= CLEAR_C_TILE;
                            end if;
                        else
                            tile_col <= tile_col + 1;
                            state    <= CLEAR_C_TILE;
                        end if;
                    else
                        tile_k <= tile_k + 1;
                        state  <= LOAD_C_REQ;
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
