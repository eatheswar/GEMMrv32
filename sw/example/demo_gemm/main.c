#include <stdint.h>
#include <neorv32.h>
#include "../gemm_lib/gemmrv_hw.h"

#define GEMMRV_MAT(ptr, r, c, s) ((gemmrv_mat){ .data = (ptr), .rows = (r), .cols = (c), .stride = (s) })
#define GEMMRV_MAT_OUT(ptr, r, c, s) ((gemmrv_mat_out){ .data = (ptr), .rows = (r), .cols = (c), .stride = (s) })

#define MATRIX_SIZE 64

// Allocate large arrays in BSS memory
int8_t raw_A[MATRIX_SIZE * MATRIX_SIZE];
int8_t raw_B[MATRIX_SIZE * MATRIX_SIZE];
int32_t raw_C_hw[MATRIX_SIZE * MATRIX_SIZE];
int32_t raw_C_sw[MATRIX_SIZE * MATRIX_SIZE];

// Simple SW GEMM for verification
void gemm_sw_basic(const int8_t* A, const int8_t* B, int32_t* C, int M, int K, int N) {
    for(int m=0; m<M; m++) {
        for(int n=0; n<N; n++) {
            int32_t acc = 0;
            for(int k=0; k<K; k++) {
                acc += (int32_t)A[m * K + k] * (int32_t)B[k * N + n];
            }
            C[m * N + n] = acc;
        }
    }
}

int main() {
    neorv32_uart0_setup(19200, 0);
    neorv32_uart0_printf("\n\n--- ENORMOUS MATRIX MULTIPLICATION DEMO ---\n");
    neorv32_uart0_printf("Size: %d x %d\n", MATRIX_SIZE, MATRIX_SIZE);

    // 1. Initialize with random-ish data
    for(int i=0; i<MATRIX_SIZE * MATRIX_SIZE; i++) {
        raw_A[i] = (i % 13) - 6; // Values between -6 and 6
        raw_B[i] = (i % 17) - 8; // Values between -8 and 8
    }

    // 2. Package into Structs
    gemmrv_mat A = GEMMRV_MAT(raw_A, MATRIX_SIZE, MATRIX_SIZE, MATRIX_SIZE);
    gemmrv_mat B = GEMMRV_MAT(raw_B, MATRIX_SIZE, MATRIX_SIZE, MATRIX_SIZE);
    gemmrv_mat_out C = GEMMRV_MAT_OUT(raw_C_hw, MATRIX_SIZE, MATRIX_SIZE, MATRIX_SIZE);

    // 3. Run Hardware
    neorv32_uart0_printf("\n[HW] Running Hardware GEMM...\n");
    uint32_t hw_start = neorv32_cpu_csr_read(CSR_MCYCLE);
    gemmrv_mult(&A, &B, &C);
    uint32_t hw_end = neorv32_cpu_csr_read(CSR_MCYCLE);
    uint32_t hw_cycles = hw_end - hw_start;
    neorv32_uart0_printf("[HW] Finished in %u cycles.\n", hw_cycles);

    // 4. Run Software for comparison
    neorv32_uart0_printf("\n[SW] Running Software GEMM (This might take a while)...\n");
    uint32_t sw_start = neorv32_cpu_csr_read(CSR_MCYCLE);
    gemm_sw_basic(raw_A, raw_B, raw_C_sw, MATRIX_SIZE, MATRIX_SIZE, MATRIX_SIZE);
    uint32_t sw_end = neorv32_cpu_csr_read(CSR_MCYCLE);
    uint32_t sw_cycles = sw_end - sw_start;
    neorv32_uart0_printf("[SW] Finished in %u cycles.\n", sw_cycles);

    // 5. Verify and Print Stats
    int errors = 0;
    for(int i=0; i<MATRIX_SIZE * MATRIX_SIZE; i++) {
        if(raw_C_hw[i] != raw_C_sw[i]) {
            errors++;
        }
    }

    neorv32_uart0_printf("\n--- FINAL RESULTS ---\n");
    neorv32_uart0_printf("Mathematical Errors: %d\n", errors);
    neorv32_uart0_printf("Hardware Cycles:     %u\n", hw_cycles);
    neorv32_uart0_printf("Software Cycles:     %u\n", sw_cycles);
    
    // Calculate speedup. Adding float point precision manually since printf doesn't support %f here.
    uint32_t speedup_int = sw_cycles / hw_cycles;
    uint32_t speedup_frac = ((sw_cycles % hw_cycles) * 100) / hw_cycles;
    neorv32_uart0_printf("Speedup:             %u.%02ux\n", speedup_int, speedup_frac);
    neorv32_uart0_printf("-------------------------------------------\n");

    return 0;
}
