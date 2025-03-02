!========================================================================
!
!                            S P E C F E M 2 D
!                            -----------------
!
!     Main historical authors: Dimitri Komatitsch and Jeroen Tromp
!                              CNRS, France
!                       and Princeton University, USA
!                 (there are currently many more authors!)
!                           (c) October 2017
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

! for poroelastic solver: update memory variables with fourth-order Runge-Kutta time scheme for attenuation

 subroutine compute_attenuation_poro_fluid_part()

  use constants, only: ZERO,NGLLX,NGLLZ,ALPHA_LDDRK,BETA_LDDRK,ALPHA_RK4,BETA_RK4

  use specfem_par, only: nspec,ispec_is_poroelastic,etastore,permstore,ibool, &
                         velocw_poroelastic,time_stepping_scheme,deltat,i_stage,time_stepping_scheme, &
                         rx_viscous,rz_viscous,viscox,viscoz, &
                         rx_viscous_force_RK,rx_viscous_initial_rk,rz_viscous_force_RK,rz_viscous_initial_rk, &
                         rx_viscous_LDDRK,rz_viscous_LDDRK, &
                         alphaval,betaval,gammaval,theta_e,theta_s,thetainv,ATTENUATION_PORO_FLUID_PART

  implicit none

  ! local variables
  integer :: i,j,ispec,iglob
  double precision :: eta_f,permlxx,permlxz,permlzz,detk,invpermlxx,invpermlxz,invpermlzz, &
                      Sn,Snp1,weight_rk
  double precision, dimension(3) :: bl_unrelaxed_elastic
  double precision :: viscox_loc,viscoz_loc

  ! checks if anything to do
  if (.not. ATTENUATION_PORO_FLUID_PART) return

  ! loop over spectral elements
  do ispec = 1,nspec

    ! only for poroelastic elements
    if (.not. ispec_is_poroelastic(ispec)) cycle

    do j = 1,NGLLZ
      do i = 1,NGLLX
        ! fluid viscosity
        eta_f = etastore(i,j,ispec)

        ! only if viscous
        if (eta_f > 0.d0) then
          permlxx = permstore(1,i,j,ispec)
          permlxz = permstore(2,i,j,ispec)
          permlzz = permstore(3,i,j,ispec)

          ! calcul of the inverse of k
          detk = permlxx * permlzz - permlxz * permlxz
          if (detk /= ZERO) then
            invpermlxx = permlzz/detk
            invpermlxz = -permlxz/detk
            invpermlzz = permlxx/detk
          else
            call stop_the_code('Permeability matrix is not invertible')
          endif

          ! relaxed viscous coef
          bl_unrelaxed_elastic(1) = eta_f*invpermlxx
          bl_unrelaxed_elastic(2) = eta_f*invpermlxz
          bl_unrelaxed_elastic(3) = eta_f*invpermlzz

          iglob = ibool(i,j,ispec)
          viscox_loc = velocw_poroelastic(1,iglob) * bl_unrelaxed_elastic(1) + &
                            velocw_poroelastic(2,iglob) * bl_unrelaxed_elastic(2)
          viscoz_loc = velocw_poroelastic(1,iglob) * bl_unrelaxed_elastic(2) + &
                            velocw_poroelastic(2,iglob) * bl_unrelaxed_elastic(3)

          ! time stepping
          select case (time_stepping_scheme)
          case (1)
            ! Newmark
            ! evolution rx_viscous
            Sn   = - (1.d0 - theta_e/theta_s)/theta_s*viscox(i,j,ispec)
            Snp1 = - (1.d0 - theta_e/theta_s)/theta_s*viscox_loc
            rx_viscous(i,j,ispec) = alphaval * rx_viscous(i,j,ispec) + betaval * Sn + gammaval * Snp1

            ! evolution rz_viscous
            Sn   = - (1.d0 - theta_e/theta_s)/theta_s*viscoz(i,j,ispec)
            Snp1 = - (1.d0 - theta_e/theta_s)/theta_s*viscoz_loc
            rz_viscous(i,j,ispec) = alphaval * rz_viscous(i,j,ispec) + betaval * Sn + gammaval * Snp1

          case (2)
            ! LDDRK
            Sn   = - (1.d0 - theta_e/theta_s)/theta_s*viscox(i,j,ispec)
            rx_viscous_LDDRK(i,j,ispec) = ALPHA_LDDRK(i_stage) * rx_viscous_LDDRK(i,j,ispec) + &
                                          deltat * (Sn + thetainv * rx_viscous(i,j,ispec))
            rx_viscous(i,j,ispec)= rx_viscous(i,j,ispec)+BETA_LDDRK(i_stage) * rx_viscous_LDDRK(i,j,ispec)

            Sn   = - (1.d0 - theta_e/theta_s)/theta_s*viscoz(i,j,ispec)
            rz_viscous_LDDRK(i,j,ispec)= ALPHA_LDDRK(i_stage) * rz_viscous_LDDRK(i,j,ispec)+&
                                         deltat * (Sn + thetainv * rz_viscous(i,j,ispec))
            rz_viscous(i,j,ispec)= rz_viscous(i,j,ispec)+BETA_LDDRK(i_stage) * rz_viscous_LDDRK(i,j,ispec)

          case (3)
            ! Runge-Kutta
            ! x-component
            ! initial field
            if (i_stage == 1) rx_viscous_initial_rk(i,j,ispec) = rx_viscous(i,j,ispec)

            ! intermediate fields
            Sn   = - (1.d0 - theta_e/theta_s)/theta_s*viscox(i,j,ispec)
            rx_viscous_force_RK(i,j,ispec,i_stage) = Sn + thetainv * rx_viscous(i,j,ispec)

            if (i_stage == 1 .or. i_stage == 2 .or. i_stage == 3) then
              ! note: this prepare the fields for the next stage, i.e., used at istage+1
              weight_rk = ALPHA_RK4(i_stage+1) * deltat
              rx_viscous(i,j,ispec) = rx_viscous_initial_rk(i,j,ispec) + weight_rk * rx_viscous_force_RK(i,j,ispec,i_stage)

            else if (i_stage == 4) then
              ! final update
              rx_viscous(i,j,ispec) = rx_viscous_initial_rk(i,j,ispec) + deltat * &
                                      (BETA_RK4(1) * rx_viscous_force_RK(i,j,ispec,1) + &
                                       BETA_RK4(2) * rx_viscous_force_RK(i,j,ispec,2) + &
                                       BETA_RK4(3) * rx_viscous_force_RK(i,j,ispec,3) + &
                                       BETA_RK4(4) * rx_viscous_force_RK(i,j,ispec,4))
            endif

            ! z-component
            ! initial field
            if (i_stage == 1) rz_viscous_initial_rk(i,j,ispec) = rz_viscous(i,j,ispec)

            ! intermediate field
            Sn   = - (1.d0 - theta_e/theta_s)/theta_s*viscoz(i,j,ispec)
            rz_viscous_force_RK(i,j,ispec,i_stage) = Sn + thetainv * rz_viscous(i,j,ispec)

            if (i_stage == 1 .or. i_stage == 2 .or. i_stage == 3) then
              ! note: this prepare the fields for the next stage, i.e., used at istage+1
              weight_rk = ALPHA_RK4(i_stage+1) * deltat
              rz_viscous(i,j,ispec) = rz_viscous_initial_rk(i,j,ispec) + weight_rk * rz_viscous_force_RK(i,j,ispec,i_stage)

            else if (i_stage == 4) then
              ! final update
              rz_viscous(i,j,ispec) = rz_viscous_initial_rk(i,j,ispec) + deltat * &
                                      (BETA_RK4(1) * rz_viscous_force_RK(i,j,ispec,1) + &
                                       BETA_RK4(2) * rz_viscous_force_RK(i,j,ispec,2) + &
                                       BETA_RK4(3) * rz_viscous_force_RK(i,j,ispec,3) + &
                                       BETA_RK4(4) * rz_viscous_force_RK(i,j,ispec,4))
            endif

          case default
            call stop_the_code('Time stepping scheme not implemented yet for poro_fluid attenuation')
          end select

          if (time_stepping_scheme == 1) then
            ! Newmark
            ! save visco for Runge-Kutta scheme when used together with Newmark
            viscox(i,j,ispec) = viscox_loc
            viscoz(i,j,ispec) = viscoz_loc
          endif
        endif ! eta_f
      enddo
    enddo

  enddo   ! end of spectral element loop

 end subroutine compute_attenuation_poro_fluid_part
