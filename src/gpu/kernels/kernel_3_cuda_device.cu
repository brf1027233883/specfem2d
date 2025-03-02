/*
!========================================================================
!
!                            S P E C F E M 2 D
!                            -----------------
!
!     Main historical authors: Dimitri Komatitsch and Jeroen Tromp
!                        Princeton University, USA
!                and CNRS / University of Marseille, France
!                 (there are currently many more authors!)
! (c) Princeton University and CNRS / University of Marseille, April 2014
!
! This software is a computer program whose purpose is to solve
! the two-dimensional viscoelastic anisotropic or poroelastic wave equation
! using a spectral-element method (SEM).
!
! This program is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 3 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License along
! with this program; if not, write to the Free Software Foundation, Inc.,
! 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
!
! The full text of the license is available in file "LICENSE".
!
!========================================================================
*/


__global__ void kernel_3_cuda_device(realw* veloc,
                                     realw* accel,
                                     int size,
                                     realw deltatover2,
                                     realw* rmassx,
                                     realw* rmassz) {

  int id = threadIdx.x + blockIdx.x*blockDim.x + blockIdx.y*gridDim.x*blockDim.x;

  // because of block and grid sizing problems, there is a small
  // amount of buffer at the end of the calculation
  if (id < size) {
    accel[2*id] = accel[2*id]*rmassx[id];
    accel[2*id+1] = accel[2*id+1]*rmassz[id];

    veloc[2*id] = veloc[2*id] + deltatover2*accel[2*id];
    veloc[2*id+1] = veloc[2*id+1] + deltatover2*accel[2*id+1];
  }

// -----------------
// total of: 34 FLOP per thread (without int id calculation at beginning)
//
//           (3 * 3 + 3 * 3) * 4 BYTE = 72 DRAM accesses per thread
//
// arithmetic intensity: 34 FLOP / 72 BYTES ~ 0.47 FLOP/BYTE
// -----------------

}

