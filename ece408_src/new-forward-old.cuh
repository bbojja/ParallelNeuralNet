
#ifndef MXNET_OPERATOR_NEW_FORWARD_CUH_
#define MXNET_OPERATOR_NEW_FORWARD_CUH_
#define TILE_WIDTH 8
#include <mxnet/base.h>

namespace mxnet
{
namespace op
{
__constant__ float k_const[2400];
__global__ void forward_kernel(float *y, const float *x, const float *k, 
                               const int B, const int M, const int C, 
                               const int H, const int W, const int K)
{   
#define y4d(i3, i2, i1, i0) y[(i3) * (M * H_out * W_out) + (i2) * (H_out * W_out) + (i1) * (W_out) + i0]
#define x4d(i3, i2, i1, i0) x[(i3) * (C * H * W) + (i2) * (H * W) + (i1) * (W) + i0]
#define k4d(i3, i2, i1, i0) k[(i3) * (C * K * K) + (i2) * (K * K) + (i1) * (K) + i0]
#define TWK (TILE_WIDTH+K)
#define x_shared3d(c,w,h) x_shared[(c)*(TWK)*(TWK)+(w)*(TWK)+(h)]
    /*
    Modify this function to implement the forward pass described in Chapter 16.
    We have added an additional dimension to the tensors to support an entire mini-batch
    The goal here is to be correct AND fast.
    We have some nice #defs for you below to simplify indexing. Feel free to use them, or create your own.
    */

    extern __shared__ float x_shared[];
    // float* x_shared = k_shared+ C*K*K;
    int b,m,h,w,c,p,q,tx,ty;
    
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;

    int W_grid = ceil(W_out / (TILE_WIDTH*1.0));
    h = (blockIdx.z / W_grid)* TILE_WIDTH + threadIdx.y;
    w = (blockIdx.z % W_grid)* TILE_WIDTH + threadIdx.x;
    

    b = blockIdx.x;
    m = blockIdx.y;
    tx = threadIdx.x;
    ty = threadIdx.y;
    //shared k
    // int cursor = ty*TILE_WIDTH+tx;
    // while(cursor<C*K*K){
    //     k_shared[cursor]=k[m*C*K*K+cursor];
    //     cursor+=TILE_WIDTH*TILE_WIDTH;
    // }

    /* load x into shared memory Type1*/
    // for (int c = 0; c < C; ++c){
    //     int s1 = threadIdx.y;
    //     while( s1 < TWK){
    //         int s2 = threadIdx.x;
    //         while( s2 < TWK){
    //             x_shared3d(c,s1,s2) = x4d(b,c, h + s1 - ty, w + s2 - tx);
    //             s2 += TILE_WIDTH;
    //         }           
    //         s1 += TILE_WIDTH;
    //     }
    // }


    /* load x into shared memory Type2*/
    for(int c=0; c<C; ++c){
        int tid = ty*TILE_WIDTH+tx;
        while(tid<TWK*TWK){
            // if(h+(tid/TWK)-ty<H && w+tid%TWK-tx<W)
                x_shared[c*TWK*TWK+tid] = x4d(b,c,h+(tid/TWK)-ty,w+(tid%TWK)-tx);
            tid+=TILE_WIDTH*TILE_WIDTH;
        }
    }
    

    __syncthreads();

    float sum = 0.0;
    if(w<W_out && h<H_out){
        for(c = 0; c<C; ++c){
            for(p=0; p<K; ++p){
                for(q =0; q<K; ++q){
                    sum+= x_shared3d(c,ty+p,tx+q)*k_const[m*C*K*K +c*K*K + p*K + q];
                }
            }
        }
        y4d(b,m,h,w) =sum;
    }
        
#undef y4d
#undef x4d
#undef k4d
#undef x_shared3d
#undef TWK
}

/* 
   This function is called by new-inl.h
   Any code you write should be executed by this function.
   For ECE408, we only expect the float version of the operator to be called, so here we specialize with only floats.
*/
template <>
void forward<gpu, float>(mshadow::Tensor<gpu, 4, float> &y,
                         const mshadow::Tensor<gpu, 4, float> &x, 
                         const mshadow::Tensor<gpu, 4, float> &w)
{
    

    // Use mxnet's CHECK_EQ to do assertions.
    // Remove this assertion when you do your implementation!
    //CHECK_EQ(0, 1) << "Remove this line and replace with your implementation";

    // Extract the tensor dimensions into B,M,C,H,W,K
    // ...
    const int B = x.shape_[0];
    const int M = y.shape_[1];
    const int C = x.shape_[1];
    const int H = x.shape_[2];
    const int W = x.shape_[3];
    const int K = w.shape_[3];
    const int H_out = H - K + 1;
    const int W_out = W - K + 1;
    printf("**********C=%d***********\n", C);
    int W_grid = ceil(W_out / (TILE_WIDTH*1.0));
    int H_grid = ceil(H_out / (TILE_WIDTH*1.0));
    int Z = H_grid * W_grid;
    // Set the kernel dimensions
    dim3 gridDim(B,M,Z);
    dim3 blockDim(TILE_WIDTH,TILE_WIDTH,1);
    // Call the kernel
    cudaMemcpyToSymbol(k_const,w.dptr_, sizeof(float)*C*K*K*M, 0);
    forward_kernel<<<gridDim,blockDim, 
                    sizeof(float)*(C*(TILE_WIDTH+K)*(TILE_WIDTH+K))>>>
                    (y.dptr_,x.dptr_,w.dptr_, B,M,C,H,W,K);

    // Use MSHADOW_CUDA_CALL to check for CUDA runtime errors.
    MSHADOW_CUDA_CALL(cudaDeviceSynchronize());
}

/* 
    This tells mxnet how to do an op when it's not a float.
    This is not used in the ECE408 project
*/
template <typename gpu, typename DType>
void forward(mshadow::Tensor<gpu, 4, DType> &y, const mshadow::Tensor<gpu, 4, DType> &x, const mshadow::Tensor<gpu, 4, DType> &w)
{
    CHECK_EQ(0,1) << "Remove this line and replace it with your implementation.";
}
}
}

#endif