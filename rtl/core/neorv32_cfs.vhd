-- ================================================================================ --
-- NEORV32 SoC - Custom Functions Subsystem (CFS) for GEMM Accelerator              --
-- ================================================================================ --

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_cfs is
  port (
    clk_i      : in  std_ulogic;
    rstn_i     : in  std_ulogic;
    req_addr_i : in  std_ulogic_vector(15 downto 0);
    req_data_i : in  std_ulogic_vector(31 downto 0);
    req_ben_i  : in  std_ulogic_vector(3 downto 0);
    req_stb_i  : in  std_ulogic;
    req_rw_i   : in  std_ulogic;
    rsp_data_o : out std_ulogic_vector(31 downto 0);
    rsp_ack_o  : out std_ulogic;
    irq_o      : out std_ulogic;
    cfs_in_i   : in  std_ulogic_vector(255 downto 0);
    cfs_out_o  : out std_ulogic_vector(255 downto 0);
    -- bus master interface --
    cfs_req_o  : out bus_req_t;
    cfs_rsp_i  : in  bus_rsp_t
  );
end entity;

architecture neorv32_cfs_rtl of neorv32_cfs is

    -- Registers
    signal reg_base_a    : std_ulogic_vector(31 downto 0);
    signal reg_base_b    : std_ulogic_vector(31 downto 0);
    signal reg_base_c    : std_ulogic_vector(31 downto 0);
    signal reg_stride    : std_ulogic_vector(31 downto 0);
    signal reg_dimension : std_ulogic_vector(31 downto 0);
    
    signal status_busy : std_ulogic;
    signal status_done : std_ulogic;
    signal cmd_start   : std_ulogic;

    -- Systolic Array PE definition
    type pe_acc_t is array(0 to 7, 0 to 7) of signed(31 downto 0);
    type pe_a_t   is array(0 to 7, 0 to 7) of signed(7 downto 0);
    type pe_b_t   is array(0 to 7, 0 to 7) of signed(7 downto 0);
    
    signal pe_acc : pe_acc_t;
    signal pe_a   : pe_a_t;
    signal pe_b   : pe_b_t;
    
    -- Ping-Pong Buffers
    type byte_array is array(0 to 63) of std_ulogic_vector(7 downto 0);
    signal a_ping, a_pong : byte_array;
    signal b_ping, b_pong : byte_array;

    -- State Machines
    type state_t is (S_IDLE, S_INIT_TILE, S_LOAD_A, S_LOAD_A_WAIT, S_LOAD_B, S_LOAD_B_WAIT, S_WAIT_COMPUTE, S_STORE_C, S_STORE_C_WAIT, S_DONE);
    signal state : state_t;

    -- AGU Counters and variables
    signal tile_i : unsigned(15 downto 0);
    signal tile_j : unsigned(15 downto 0);
    signal tile_k : unsigned(15 downto 0);
    signal read_cnt : unsigned(4 downto 0);
    signal write_cnt : unsigned(6 downto 0);
    
    signal ping_pong_sel : std_ulogic;
    
    -- Compute FSM
    type comp_state_t is (C_IDLE, C_COMPUTE, C_WAIT);
    signal comp_state : comp_state_t;
    signal comp_cnt : unsigned(4 downto 0);
    signal comp_start : std_ulogic;
    signal comp_done : std_ulogic;
    signal comp_clear_acc : std_ulogic;
    
    -- Bus interfacing
    signal bus_req : bus_req_t;
    
    signal a_in : pe_a_t;
    signal b_in : pe_b_t;

begin

    cfs_out_o <= (others => '0');
    irq_o <= status_done;
    cfs_req_o <= bus_req;

    -- MMIO Access
    process(rstn_i, clk_i)
    begin
        if rstn_i = '0' then
            reg_base_a <= (others => '0');
            reg_base_b <= (others => '0');
            reg_base_c <= (others => '0');
            reg_stride <= (others => '0');
            reg_dimension <= (others => '0');
            cmd_start <= '0';
            status_done <= '0';
            rsp_ack_o <= '0';
            rsp_data_o <= (others => '0');
        elsif rising_edge(clk_i) then
            rsp_ack_o <= req_stb_i;
            rsp_data_o <= (others => '0');
            cmd_start <= '0';
            
            if status_done = '1' and req_stb_i = '1' and req_rw_i = '1' and req_addr_i(15 downto 2) = "00000000000101" then
                if req_data_i(2) = '0' then
                    status_done <= '0';
                end if;
            end if;
            
            if state = S_DONE then
                status_done <= '1';
                 
            end if;

            if req_stb_i = '1' then
                if req_rw_i = '1' then
                    case req_addr_i(15 downto 2) is
                        when "00000000000000" => reg_base_a <= req_data_i;
                        when "00000000000001" => reg_base_b <= req_data_i;
                        when "00000000000010" => reg_base_c <= req_data_i;
                        when "00000000000011" => reg_stride <= req_data_i;
                        when "00000000000100" => reg_dimension <= req_data_i;
                        when "00000000000101" => 
                            if req_data_i(0) = '1' then
                                cmd_start <= '1';
                                status_done <= '0';
                            else
                                cmd_start <= '0';
                            end if;
                        when others => null;
                    end case;
                else
                    case req_addr_i(15 downto 2) is
                        when "00000000000000" => rsp_data_o <= reg_base_a;
                        when "00000000000001" => rsp_data_o <= reg_base_b;
                        when "00000000000010" => rsp_data_o <= reg_base_c;
                        when "00000000000011" => rsp_data_o <= reg_stride;
                        when "00000000000100" => rsp_data_o <= reg_dimension;
                        when "00000000000101" => 
                            rsp_data_o(0) <= '0';
                            rsp_data_o(1) <= status_busy;
                            rsp_data_o(2) <= status_done;
                            rsp_data_o(31 downto 3) <= (others => '0');
                        when others => rsp_data_o <= (others => '0');
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- Master AGU FSM
    process(rstn_i, clk_i)
        variable base_addr : unsigned(31 downto 0);
        variable offset : unsigned(31 downto 0);
        variable row : unsigned(15 downto 0);
        variable col : unsigned(15 downto 0);
        variable word_idx : unsigned(15 downto 0);
    begin
        if rstn_i = '0' then
            state <= S_IDLE;
            status_busy <= '0';
            bus_req <= req_terminate_c;
            tile_i <= (others => '0');
            tile_j <= (others => '0');
            tile_k <= (others => '0');
            read_cnt <= (others => '0');
            write_cnt <= (others => '0');
            ping_pong_sel <= '0';
            comp_start <= '0';
            comp_clear_acc <= '0';
        elsif rising_edge(clk_i) then
            comp_start <= '0';
            comp_clear_acc <= '0';
            bus_req.stb <= '0';
            
            case state is
                when S_IDLE =>
                    bus_req.stb <= '0';
                    bus_req.stb <= '0';
                    if cmd_start = '1' and status_done = '0' then
                        state <= S_INIT_TILE;
                        status_busy <= '1';
                        tile_i <= (others => '0');
                        tile_j <= (others => '0');
                        tile_k <= (others => '0');
                    else
                        status_busy <= '0';
                    end if;
                    
                when S_INIT_TILE =>
                    comp_clear_acc <= '1';
                    tile_k <= (others => '0');
                    ping_pong_sel <= '0';
                    state <= S_LOAD_A;
                    read_cnt <= (others => '0');
                    
                when S_LOAD_A =>
                    row := resize(tile_i * 8, 16) + resize(read_cnt(4 downto 1), 16);
                    col := resize(tile_k * 8, 16) + resize(read_cnt(0 downto 0) & "00", 16);
                    base_addr := unsigned(reg_base_a);
                    offset := resize(row * unsigned(reg_stride(15 downto 0)), 32) + resize(col, 32);
                    bus_req.addr <= std_ulogic_vector(base_addr + offset);
                    bus_req.data <= (others => '0');
                    bus_req.ben <= "1111";
                    bus_req.rw <= '0';
                    bus_req.stb <= '1';
                    state <= S_LOAD_A_WAIT;
                    
                when S_LOAD_A_WAIT =>
                    if cfs_rsp_i.ack = '1' then
                        bus_req.stb <= '0';
                        if ping_pong_sel = '0' then
                            a_ping(to_integer(read_cnt)*4 + 0) <= cfs_rsp_i.data(7 downto 0);
                            a_ping(to_integer(read_cnt)*4 + 1) <= cfs_rsp_i.data(15 downto 8);
                            a_ping(to_integer(read_cnt)*4 + 2) <= cfs_rsp_i.data(23 downto 16);
                            a_ping(to_integer(read_cnt)*4 + 3) <= cfs_rsp_i.data(31 downto 24);
                        else
                            a_pong(to_integer(read_cnt)*4 + 0) <= cfs_rsp_i.data(7 downto 0);
                            a_pong(to_integer(read_cnt)*4 + 1) <= cfs_rsp_i.data(15 downto 8);
                            a_pong(to_integer(read_cnt)*4 + 2) <= cfs_rsp_i.data(23 downto 16);
                            a_pong(to_integer(read_cnt)*4 + 3) <= cfs_rsp_i.data(31 downto 24);
                        end if;
                        if read_cnt = 15 then
                            read_cnt <= (others => '0');
                            state <= S_LOAD_B;
                        else
                            read_cnt <= read_cnt + 1;
                            state <= S_LOAD_A;
                        end if;
                    end if;
                    
                when S_LOAD_B =>
                    row := resize(tile_k * 8, 16) + resize(read_cnt(4 downto 1), 16);
                    col := resize(tile_j * 8, 16) + resize(read_cnt(0 downto 0) & "00", 16);
                    base_addr := unsigned(reg_base_b);
                    offset := resize(row * unsigned(reg_stride(15 downto 0)), 32) + resize(col, 32);
                    bus_req.addr <= std_ulogic_vector(base_addr + offset);
                    bus_req.data <= (others => '0');
                    bus_req.ben <= "1111";
                    bus_req.rw <= '0';
                    bus_req.stb <= '1';
                    state <= S_LOAD_B_WAIT;
                    
                when S_LOAD_B_WAIT =>
                    if cfs_rsp_i.ack = '1' then
                        bus_req.stb <= '0';
                        if ping_pong_sel = '0' then
                            b_ping(to_integer(read_cnt)*4 + 0) <= cfs_rsp_i.data(7 downto 0);
                            b_ping(to_integer(read_cnt)*4 + 1) <= cfs_rsp_i.data(15 downto 8);
                            b_ping(to_integer(read_cnt)*4 + 2) <= cfs_rsp_i.data(23 downto 16);
                            b_ping(to_integer(read_cnt)*4 + 3) <= cfs_rsp_i.data(31 downto 24);
                        else
                            b_pong(to_integer(read_cnt)*4 + 0) <= cfs_rsp_i.data(7 downto 0);
                            b_pong(to_integer(read_cnt)*4 + 1) <= cfs_rsp_i.data(15 downto 8);
                            b_pong(to_integer(read_cnt)*4 + 2) <= cfs_rsp_i.data(23 downto 16);
                            b_pong(to_integer(read_cnt)*4 + 3) <= cfs_rsp_i.data(31 downto 24);
                        end if;
                        if read_cnt = 15 then
                            read_cnt <= (others => '0');
                            comp_start <= '1';
                            if tile_k = 0 then
                                comp_clear_acc <= '1';
                            end if;
                            state <= S_WAIT_COMPUTE;
                        else
                            read_cnt <= read_cnt + 1;
                            state <= S_LOAD_B;
                        end if;
                    end if;

                when S_WAIT_COMPUTE =>
                    if comp_done = '1' then
                        if resize((tile_k + 1) * 8, 16) < unsigned(reg_dimension(15 downto 0)) then
                            tile_k <= tile_k + 1;
                            ping_pong_sel <= not ping_pong_sel;
                            read_cnt <= (others => '0');
                            state <= S_LOAD_A;
                        else
                            write_cnt <= (others => '0');
                            state <= S_STORE_C;
                        end if;
                    end if;
                    
                when S_STORE_C =>
                    row := resize(tile_i * 8, 16) + resize(write_cnt(5 downto 3), 16);
                    col := resize(tile_j * 8, 16) + resize(write_cnt(2 downto 0), 16);
                    base_addr := unsigned(reg_base_c);
                    offset := resize((resize(row * unsigned(reg_stride(15 downto 0)), 32) + resize(col, 32)) * 4, 32);
                    bus_req.addr <= std_ulogic_vector(base_addr + offset);
                    bus_req.data <= std_ulogic_vector(pe_acc(to_integer(write_cnt(5 downto 3)), to_integer(write_cnt(2 downto 0))));
                    bus_req.ben <= "1111";
                    bus_req.rw <= '1';
                    bus_req.stb <= '1';
                    state <= S_STORE_C_WAIT;
                    
                when S_STORE_C_WAIT =>
                    if cfs_rsp_i.ack = '1' then
                        bus_req.stb <= '0';
                        if write_cnt = 63 then
                            if resize((tile_j + 1) * 8, 16) < unsigned(reg_dimension(15 downto 0)) then
                                tile_j <= tile_j + 1;
                                state <= S_INIT_TILE;
                            else
                                tile_j <= (others => '0');
                                if resize((tile_i + 1) * 8, 16) < unsigned(reg_dimension(15 downto 0)) then
                                    tile_i <= tile_i + 1;
                                    state <= S_INIT_TILE;
                                else
                                     
                                    state <= S_DONE;
                                end if;
                            end if;
                        else
                            write_cnt <= write_cnt + 1;
                            state <= S_STORE_C;
                        end if;
                    end if;

                when S_DONE =>
                    state <= S_IDLE;
            end case;
        end if;
    end process;
    
    -- Compute FSM and Systolic Array
    process(rstn_i, clk_i)
    begin
        if rstn_i = '0' then
            comp_state <= C_IDLE;
            comp_cnt <= (others => '0');
            comp_done <= '0';
            for r in 0 to 7 loop
                for c in 0 to 7 loop
                    pe_acc(r, c) <= (others => '0');
                    pe_a(r, c) <= (others => '0');
                    pe_b(r, c) <= (others => '0');
                end loop;
            end loop;
        elsif rising_edge(clk_i) then
            comp_done <= '0';
            
            if comp_clear_acc = '1' then
                for r in 0 to 7 loop
                    for c in 0 to 7 loop
                        pe_acc(r, c) <= (others => '0');
                    end loop;
                end loop;
            end if;
            
            case comp_state is
                when C_IDLE =>
                    if comp_start = '1' then
                        comp_state <= C_COMPUTE;
                        comp_cnt <= (others => '0');
                    end if;
                    
                when C_COMPUTE =>
                    -- 15 cycles of compute
                    -- In each cycle, shift A right and B down
                    for r in 0 to 7 loop
                        for c in 0 to 7 loop
                            pe_acc(r, c) <= pe_acc(r, c) + resize(pe_a(r, c) * pe_b(r, c), 32);
                            
                            if c = 0 then
                                if (comp_cnt >= r) and (comp_cnt - r < 8) then
                                    if ping_pong_sel = '0' then
                                        pe_a(r, c) <= signed(a_ping(r * 8 + to_integer(comp_cnt - r)));
                                    else
                                        pe_a(r, c) <= signed(a_pong(r * 8 + to_integer(comp_cnt - r)));
                                    end if;
                                else
                                    pe_a(r, c) <= (others => '0');
                                end if;
                            else
                                pe_a(r, c) <= pe_a(r, c-1);
                            end if;
                            
                            if r = 0 then
                                if (comp_cnt >= c) and (comp_cnt - c < 8) then
                                    if ping_pong_sel = '0' then
                                        pe_b(r, c) <= signed(b_ping(to_integer(comp_cnt - c) * 8 + c));
                                    else
                                        pe_b(r, c) <= signed(b_pong(to_integer(comp_cnt - c) * 8 + c));
                                    end if;
                                else
                                    pe_b(r, c) <= (others => '0');
                                end if;
                            else
                                pe_b(r, c) <= pe_b(r-1, c);
                            end if;
                        end loop;
                    end loop;
                    
                    if comp_cnt = 22 then
                        comp_state <= C_IDLE;
                        comp_done <= '1';
                    else
                        comp_cnt <= comp_cnt + 1;
                    end if;
                    
                when others =>
                    comp_state <= C_IDLE;
            end case;
        end if;
    end process;

end architecture;
