library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.matrix_tiled_pkg.all;

entity matrix_mult_tiled_core is
    generic (
        N                   : positive := 128;
        TILE_SIZE           : positive := 4;
        NUM_MACS            : positive := 4;
        DATA_WIDTH          : positive := 8;
        ACC_WIDTH           : positive := 32;
        MEM_TYPE            : string := "internal_fpga_ram";
        DATAFLOW            : string := "output_stationary";
        BUFFERING_MODE      : string := "single";
        MEMORY_BURST_LEN    : natural := 1;
        MAC_PIPELINE_STAGES : natural := 0;
        MEMORY_BANKS_A      : positive := 1;
        MEMORY_BANKS_B      : positive := 1
    );
    port (
        clk : in std_logic;
        rst : in std_logic;

        wr_en      : in std_logic;
        matrix_sel : in std_logic; -- '0' = A, '1' = B
        wr_addr    : in unsigned(clog2(N*N)-1 downto 0);
        data_in    : in signed(DATA_WIDTH-1 downto 0);

        start : in std_logic;
        busy  : out std_logic;
        done  : out std_logic;

        result_addr : in unsigned(clog2(N*N)-1 downto 0);
        data_out    : out signed(ACC_WIDTH-1 downto 0)
    );
end entity matrix_mult_tiled_core;

architecture rtl of matrix_mult_tiled_core is

    constant MATRIX_ELEMS : positive := N * N;
    constant ADDR_WIDTH   : positive := clog2(MATRIX_ELEMS);
    constant TILE_ELEMS   : positive := TILE_SIZE * TILE_SIZE;
    constant NUM_TILES    : positive := N / TILE_SIZE;

    subtype data_t is signed(DATA_WIDTH-1 downto 0);
    subtype acc_t  is signed(ACC_WIDTH-1 downto 0);

    type data_tile_t is array (0 to TILE_ELEMS-1) of data_t;
    type acc_tile_t  is array (0 to TILE_ELEMS-1) of acc_t;

    type state_t is (
        IDLE,
        CLEAR_C_TILE,
        LOAD_C_ADDR,
        LOAD_C_WAIT,
        LOAD_C_CAPTURE,
        LOAD_AB_ADDR,
        LOAD_AB_WAIT,
        LOAD_AB_CAPTURE,
        START_CORE,
        WAIT_CORE,
        CAPTURE_CORE,
        WRITE_C,
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

    signal a_wr_en   : std_logic := '0';
    signal a_addr    : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal a_wr_data : data_t := (others => '0');
    signal a_rd_data : data_t;

    signal b_wr_en   : std_logic := '0';
    signal b_addr    : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal b_wr_data : data_t := (others => '0');
    signal b_rd_data : data_t;

    signal c_wr_en   : std_logic := '0';
    signal c_addr    : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
    signal c_wr_data : acc_t := (others => '0');
    signal c_rd_data : acc_t;

    signal core_start : std_logic := '0';
    signal core_done  : std_logic;
    signal core_mac_ops_issued_unused : unsigned(31 downto 0);

    signal core_a_tile     : std_logic_vector((TILE_ELEMS*DATA_WIDTH)-1 downto 0);
    signal core_b_tile     : std_logic_vector((TILE_ELEMS*DATA_WIDTH)-1 downto 0);
    signal core_c_tile_in  : std_logic_vector((TILE_ELEMS*ACC_WIDTH)-1 downto 0);
    signal core_c_tile_out : std_logic_vector((TILE_ELEMS*ACC_WIDTH)-1 downto 0);

    function linear_addr(
        constant row_idx : natural;
        constant col_idx : natural
    ) return unsigned is
    begin
        return to_unsigned(row_idx * N + col_idx, ADDR_WIDTH);
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
        report "N precisa ser multiplo de TILE_SIZE."
        severity failure;

    assert DATAFLOW = "output_stationary"
        report "DATAFLOW diferente de output_stationary ainda nao altera o datapath deste core."
        severity warning;

    assert MEM_TYPE = "internal_fpga_ram"
        report "MEM_TYPE diferente de internal_fpga_ram ainda usa a implementacao interna deste core."
        severity warning;

    assert BUFFERING_MODE = "single" or BUFFERING_MODE = "double"
        report "BUFFERING_MODE deve ser single ou double."
        severity failure;

    assert MEMORY_BURST_LEN >= 1
        report "MEMORY_BURST_LEN precisa ser >= 1."
        severity failure;

    assert MEMORY_BANKS_A >= 1 and MEMORY_BANKS_B >= 1
        report "MEMORY_BANKS_A/B precisam ser >= 1."
        severity failure;

    busy <= busy_reg;
    done <= done_reg;
    data_out <= c_rd_data;

    core_a_tile    <= pack_data_tile(a_tile);
    core_b_tile    <= pack_data_tile(b_tile);
    core_c_tile_in <= pack_acc_tile(c_tile);

    u_ram_a : entity work.matrix_single_port_ram
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH,
            DEPTH      => MATRIX_ELEMS
        )
        port map (
            clk     => clk,
            wr_en   => a_wr_en,
            addr    => a_addr,
            wr_data => a_wr_data,
            rd_data => a_rd_data
        );

    u_ram_b : entity work.matrix_single_port_ram
        generic map (
            DATA_WIDTH => DATA_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH,
            DEPTH      => MATRIX_ELEMS
        )
        port map (
            clk     => clk,
            wr_en   => b_wr_en,
            addr    => b_addr,
            wr_data => b_wr_data,
            rd_data => b_rd_data
        );

    u_ram_c : entity work.matrix_single_port_ram
        generic map (
            DATA_WIDTH => ACC_WIDTH,
            ADDR_WIDTH => ADDR_WIDTH,
            DEPTH      => MATRIX_ELEMS
        )
        port map (
            clk     => clk,
            wr_en   => c_wr_en,
            addr    => c_addr,
            wr_data => c_wr_data,
            rd_data => c_rd_data
        );

    u_compute : entity work.matrix_tiled_compute_core
        generic map (
            TILE_SIZE           => TILE_SIZE,
            NUM_MACS            => NUM_MACS,
            DATA_WIDTH          => DATA_WIDTH,
            ACC_WIDTH           => ACC_WIDTH,
            MAC_PIPELINE_STAGES => MAC_PIPELINE_STAGES
        )
        port map (
            clk        => clk,
            rst        => rst,
            start      => core_start,
            done       => core_done,
            a_tile     => core_a_tile,
            b_tile     => core_b_tile,
            c_tile_in  => core_c_tile_in,
            c_tile_out => core_c_tile_out,
            mac_ops_issued => core_mac_ops_issued_unused
        );

    process(clk, rst)
        variable local_row : natural;
        variable local_col : natural;
    begin
        if rst = '1' then
            state      <= IDLE;
            tile_row   <= 0;
            tile_col   <= 0;
            tile_k     <= 0;
            tile_idx   <= 0;
            a_tile     <= (others => (others => '0'));
            b_tile     <= (others => (others => '0'));
            c_tile     <= (others => (others => '0'));
            busy_reg   <= '0';
            done_reg   <= '0';
            core_start <= '0';

            a_wr_en   <= '0';
            a_addr    <= (others => '0');
            a_wr_data <= (others => '0');
            b_wr_en   <= '0';
            b_addr    <= (others => '0');
            b_wr_data <= (others => '0');
            c_wr_en   <= '0';
            c_addr    <= (others => '0');
            c_wr_data <= (others => '0');

        elsif rising_edge(clk) then
            core_start <= '0';
            a_wr_en    <= '0';
            b_wr_en    <= '0';
            c_wr_en    <= '0';

            if busy_reg = '0' then
                a_addr <= wr_addr;
                b_addr <= wr_addr;
                c_addr <= result_addr;

                a_wr_data <= data_in;
                b_wr_data <= data_in;

                if wr_en = '1' then
                    if matrix_sel = '0' then
                        a_wr_en <= '1';
                    else
                        b_wr_en <= '1';
                    end if;
                end if;
            end if;

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
                    busy_reg <= '1';
                    done_reg <= '0';
                    c_tile   <= (others => (others => '0'));
                    tile_idx <= 0;
                    state    <= LOAD_AB_ADDR;

                when LOAD_C_ADDR =>
                    local_row := tile_row_of(tile_idx);
                    local_col := tile_col_of(tile_idx);
                    c_addr <= linear_addr(tile_row * TILE_SIZE + local_row,
                                          tile_col * TILE_SIZE + local_col);
                    state <= LOAD_C_WAIT;

                when LOAD_C_WAIT =>
                    state <= LOAD_C_CAPTURE;

                when LOAD_C_CAPTURE =>
                    c_tile(tile_idx) <= c_rd_data;

                    if tile_idx = TILE_ELEMS-1 then
                        tile_idx <= 0;
                        state    <= LOAD_AB_ADDR;
                    else
                        tile_idx <= tile_idx + 1;
                        state    <= LOAD_C_ADDR;
                    end if;

                when LOAD_AB_ADDR =>
                    local_row := tile_row_of(tile_idx);
                    local_col := tile_col_of(tile_idx);

                    a_addr <= linear_addr(tile_row * TILE_SIZE + local_row,
                                          tile_k * TILE_SIZE + local_col);
                    b_addr <= linear_addr(tile_k * TILE_SIZE + local_row,
                                          tile_col * TILE_SIZE + local_col);
                    state <= LOAD_AB_WAIT;

                when LOAD_AB_WAIT =>
                    state <= LOAD_AB_CAPTURE;

                when LOAD_AB_CAPTURE =>
                    a_tile(tile_idx) <= a_rd_data;
                    b_tile(tile_idx) <= b_rd_data;

                    if tile_idx = TILE_ELEMS-1 then
                        tile_idx <= 0;
                        state    <= START_CORE;
                    else
                        tile_idx <= tile_idx + 1;
                        state    <= LOAD_AB_ADDR;
                    end if;

                when START_CORE =>
                    core_start <= '1';
                    state      <= WAIT_CORE;

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
                    state    <= WRITE_C;

                when WRITE_C =>
                    local_row := tile_row_of(tile_idx);
                    local_col := tile_col_of(tile_idx);

                    c_addr <= linear_addr(tile_row * TILE_SIZE + local_row,
                                          tile_col * TILE_SIZE + local_col);
                    c_wr_data <= c_tile(tile_idx);
                    c_wr_en   <= '1';

                    if tile_idx = TILE_ELEMS-1 then
                        tile_idx <= 0;
                        state    <= ADVANCE_TILE;
                    else
                        tile_idx <= tile_idx + 1;
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
                        state  <= LOAD_C_ADDR;
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
