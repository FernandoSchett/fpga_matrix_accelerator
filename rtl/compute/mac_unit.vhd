library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity mac_unit is
    generic (
        DATA_WIDTH      : positive := 16;
        ACC_WIDTH       : positive := 32;
        PIPELINE_STAGES : natural := 0
    );
    port (
        clk     : in  std_logic;
        rst     : in  std_logic;
        a       : in  signed(DATA_WIDTH-1 downto 0);
        b       : in  signed(DATA_WIDTH-1 downto 0);
        acc_in  : in  signed(ACC_WIDTH-1 downto 0);
        acc_out : out signed(ACC_WIDTH-1 downto 0)
    );
end entity mac_unit;

architecture rtl of mac_unit is
    function calc_pipe_depth(constant stages : natural) return positive is
    begin
        if stages = 0 then
            return 1;
        end if;

        return stages;
    end function;

    constant PIPE_DEPTH : positive := calc_pipe_depth(PIPELINE_STAGES);

    type pipe_t is array (0 to PIPE_DEPTH-1) of signed(ACC_WIDTH-1 downto 0);

    signal comb_result : signed(ACC_WIDTH-1 downto 0);
    signal pipe_regs   : pipe_t := (others => (others => '0'));
begin

    comb_result <= acc_in + resize(a * b, ACC_WIDTH);

    gen_comb : if PIPELINE_STAGES = 0 generate
    begin
        acc_out <= comb_result;
    end generate gen_comb;

    gen_pipe : if PIPELINE_STAGES > 0 generate
    begin
        process(clk, rst)
            variable shift_idx : natural;
        begin
            if rst = '1' then
                pipe_regs <= (others => (others => '0'));
            elsif rising_edge(clk) then
                pipe_regs(0) <= comb_result;

                shift_idx := 1;
                while shift_idx < PIPE_DEPTH loop
                    pipe_regs(shift_idx) <= pipe_regs(shift_idx-1);
                    shift_idx := shift_idx + 1;
                end loop;
            end if;
        end process;

        acc_out <= pipe_regs(PIPE_DEPTH-1);
    end generate gen_pipe;

end architecture rtl;
