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

  subroutine read_materials(f0)

! reads properties of a 2D isotropic or anisotropic linear elastic element

  use constants, only: IIN,IMAIN,ZERO,FOUR_THIRDS,TWO_THIRDS,HALF,TINYVAL, &
                       ISOTROPIC_MATERIAL,ANISOTROPIC_MATERIAL,POROELASTIC_MATERIAL

  use specfem_par, only: AXISYM,density,porosity,tortuosity,anisotropycoef,permeability,poroelastcoef, &
                          numat,myrank,QKappa_attenuationcoef,Qmu_attenuationcoef, &
                          freq0_poroelastic,Q0_poroelastic,ATTENUATION_PORO_FLUID_PART,assign_external_model,tomo_material,myrank

  implicit none

  ! frequency used for poroelastic velocities
  double precision,intent(in) :: f0

  ! local parameters
  double precision :: lambdaplus2mu,kappa,compaction_grad
  double precision :: young,poisson,cp,cs,mu,two_mu,lambda,QKappa,Qmu
  double precision :: lambdaplus2mu_s,lambdaplus2mu_fr,kappa_s,kappa_f,kappa_fr
  double precision :: young_s,poisson_s,density_mat(2),phi,tortuosity_mat
  double precision :: cpIsquare,cpIIsquare,cssquare,mu_s,mu_fr,eta_f,lambda_s,lambda_fr,perm_xx
  double precision :: c11,c13,c15,c33,c35,c55,c12,c23,c25,c22
  double precision :: val0,val1,val2,val3,val4,val5,val6,val7,val8,val9,val10,val11,val12

  double precision :: D_biot,H_biot,C_biot,M_biot

  double precision :: w_c
  integer :: imat,n,indic

  !
  !---- loop over the different material sets
  !
  density(:,:) = ZERO
  porosity(:) = ZERO
  tortuosity(:) = ZERO
  permeability(:,:) = ZERO

  poroelastcoef(:,:,:) = ZERO
  anisotropycoef(:,:) = ZERO

  QKappa_attenuationcoef(:) = 9999.
  Qmu_attenuationcoef(:) = 9999.

  ! Index of the material that will be defined by an external tomo file if needed (TOMOGRAPHY_FILE)
  tomo_material = 0

  ! user output
  ! number of materials
  if (myrank == 0) write(IMAIN,100) numat

  ! skips material sets header
  do imat = 1,numat
    ! initializes
    cp = ZERO
    cs = ZERO
    c11 = ZERO
    c13 = ZERO
    c15 = ZERO
    c33 = ZERO
    c35 = ZERO
    c55 = ZERO
    c12 = ZERO
    c23 = ZERO
    c25 = ZERO
    c22 = ZERO
    Qkappa = 9999.
    Qmu = 9999.

    ! supported model formats:
    !  acoustic                - model_number  1 rho    Vp   0   0   0 QKappa Qmu   0   0   0    0      0   0
    !  elastic                 - model_number  1 rho    Vp  Vs   0   0 QKappa Qmu   0   0   0    0      0   0
    !  anisotropic             - model_number  2 rho   c11 c13 c15 c33    c35 c55 c12 c23 c25    0 QKappa Qmu
    !  anisotropic (in AXISYM) - model_number  2 rho   c11 c13 c15 c33    c35 c55 c12 c23 c25  c22 QKappa Qmu
    !  poroelastic             - model_number  3 rhos rhof phi   c kxx    kxz kzz  Ks  Kf Kfr etaf   mufr Qmu
    !  tomo                    - model_number -1 0       0   A   0   0      0   0   0   0   0    0      0   0
    read(IIN) n,indic,val0,val1,val2,val3,val4,val5,val6,val7,val8,val9,val10,val11,val12

    if (n < 1 .or. n > numat) call exit_MPI(myrank,'Wrong material set number')

    !---- isotropic material, P and S velocities given, allows for declaration of elastic/acoustic material
    !---- elastic (cs /= 0) and acoustic (cs = 0)
    if (indic == ISOTROPIC_MATERIAL) then
      ! isotropic elastic/acoustic material

      ! line format:
      ! #model_number  #1 #(val0)rho #(val1)Vp #(val2)Vs #(val3)0 #(val4)0 #(val5)QKappa #(val6)Qmu  0 0 0 0 0 0
      density_mat(1) = val0

      ! P and S velocity
      cp = val1
      cs = val2
      compaction_grad = val3

      ! QKappa and Qmu values
      QKappa = val5
      Qmu = val6
      if (QKappa <= 0.0000001 .or. Qmu <= 0.0000001) then
        call stop_the_code( &
'negative or null values of Q attenuation factor not allowed; set them equal to 9999 to indicate no attenuation')
      endif

      ! Lame parameters
      lambdaplus2mu = density_mat(1) * cp*cp
      mu = density_mat(1) * cs*cs
      two_mu = 2.d0*mu
      lambda = lambdaplus2mu - two_mu

      ! bulk modulus Kappa
      if (AXISYM) then ! CHECK kappa
        kappa = lambda + TWO_THIRDS * mu
      else
        kappa = lambda + mu
      endif

      ! Young modulus
      young = 9.d0*kappa*mu/(3.d0*kappa + mu)

      ! Poisson's ratio
      poisson = 0.5d0*(cp*cp-2.d0*cs*cs) / (cp*cp-cs*cs)

      ! Poisson's ratio must be between -1 and +1/2
      if (poisson < -1.d0 .or. poisson > 0.5d0) call exit_MPI(myrank,'Poisson''s ratio out of range')

    !---- anisotropic material, c11, c13, c33 and c44 given in Pascal
    else if (indic == ANISOTROPIC_MATERIAL) then
      ! anisotropic elastic material

      ! line format:
      ! #model_number  #2 #(val0)rho #(val1)c11 #(val2)c13 #(val3)c15 #(val4)c33 #(val5)c35 #(val6)c55 #(val7)c12  ..
      !       ..          #(val8)c23 #(val9)c25 #(val10)c22 #(val11)QKappa #(val12)Qmu
      density_mat(1) = val0

      ! Anisotropy parameters
      c11 = val1
      c13 = val2
      c15 = val3
      c33 = val4
      c35 = val5
      c55 = val6  ! c55 == mu
      c12 = val7
      c23 = val8
      c25 = val9
      c22 = val10  ! This value is used for AXISYM only

      ! note for isotropy:
      !   c11 == c33
      !   c55 == (c11 - c13)/2
      !   c15 == c35 == c12 == c23 == c25 == 0

      ! QKappa and Qmu values
      ! old format uses 0 0 at the line end, without specifying Qkappa and Qmu. just use Q values when a positive value given.
      if (val11 > 0.1) QKappa = val11
      if (val12 > 0.1) Qmu = val12

      ! P and S velocity
      cp = sqrt(c33/density_mat(1))
      cs = sqrt(c55/density_mat(1))

      ! Lame parameters
      lambdaplus2mu = density_mat(1) * cp*cp
      mu = density_mat(1) * cs*cs
      two_mu = 2.d0*mu
      lambda = lambdaplus2mu - two_mu

      ! checks if anisotropic material has shear
      if (mu < 0.1) then
        ! zero shear, not elastic
        call exit_MPI(myrank,'Error anisotropic material has an invalid zero shear modulus')
      endif

      ! bulk modulus Kappa
      if (AXISYM) then ! CHECK kappa
        kappa = lambda + TWO_THIRDS * mu
      else
        kappa = lambda + mu
      endif

      ! Young, Poisson not used any further - just in case:
      ! Young modulus
      young = 9.d0*kappa*mu/(3.d0*kappa + mu)
      ! Poisson's ratio
      poisson = HALF * (3.d0*kappa-two_mu)/(3.d0*kappa+mu)
      !poisson = 0.5d0*(cp*cp-2.d0*cs*cs) / (cp*cp-cs*cs)   ! using Vp,Vs

      ! debug
      !print *,'debug: anisotropic lambda/mu',lambda,mu,'kappa/young/poisson',kappa,young,poisson

    !---- isotropic material, moduli are given, allows for declaration of poroelastic material
    !---- poroelastic (0 < phi < 1)
    else if (indic == POROELASTIC_MATERIAL) then
      ! poroelastic material

      ! line format:
      ! #model_number  #3 #(val0)rhos #(val1)rhof #(val2)phi #(val3)c #(val4)kxx #(val5)kxz #(val6)kzz #(val7)Ks ..
      !                .. #(val8)Kf #(val9)Kfr #(val10)etaf #(val11)mufr #(val12)Qmu
      density_mat(1) = val0
      density_mat(2) = val1

      ! porosity (phi)
      phi = val2

      ! tortuosity (kappa)
      tortuosity_mat = val3

      ! permeability
      perm_xx = val4

      ! Solid properties
      kappa_s = val7
      mu_s = val11

      ! Fluid properties
      kappa_f = val8
      eta_f = val10

      ! Frame properties
      kappa_fr = val9
      mu_fr = val11

      ! Qmu values
      ! old format uses 0 at the line end, without specifying Qmu. just use Q values when a positive value given.
      if (val12 > 0.1) Qmu = val12
      ! no bulk attenuation Qkappa supported yet..

      ! Lame parameters for the solid phase and the frame
      !if (AXISYM) then ! ABAB !! Warning !! This is false for plane strain (look for: bulk modulus plane strain) Check Kappa
        lambdaplus2mu_s = kappa_s + FOUR_THIRDS*mu_s
        lambda_s = lambdaplus2mu_s - 2.d0*mu_s
        lambdaplus2mu_fr = kappa_fr + FOUR_THIRDS*mu_fr
        lambda_fr = lambdaplus2mu_fr - 2.d0*mu_fr
      !else ! Correct lines:
      !  lambdaplus2mu_s = kappa_s - mu_s
      !  lambda_s = lambdaplus2mu_s - 2.d0*mu_s
      !  lambdaplus2mu_fr = kappa_fr - mu_fr
      !  lambda_fr = lambdaplus2mu_fr - 2.d0*mu_fr
      !endif

      ! Biot coefficients for the input phi
      call get_poroelastic_Biot_coeff(phi,kappa_s,kappa_f,kappa_fr,mu_fr,D_biot,H_biot,C_biot,M_biot)

      ! gets cpI,cpII and cs
      ! note: velocities become frequency dependent due to viscous resistance in fluid phase
      !       to avoid dependency of a source frequency, we assume here that the source frequency
      !       and viscous attenuation frequency
      call get_poroelastic_velocities(cpIsquare,cpIIsquare,cssquare, &
                                      H_biot,C_biot,M_biot,mu_fr,phi, &
                                      tortuosity_mat,density_mat(1),density_mat(2),eta_f,perm_xx, &
                                      f0,freq0_poroelastic,Q0_poroelastic,w_c,ATTENUATION_PORO_FLUID_PART)

      porosity(n) = val2  ! phi
      tortuosity(n) = val3 ! tort

      permeability(1,n) = val4 ! perm_xx
      permeability(2,n) = val5 ! perm_xz
      permeability(3,n) = val6 ! perm_zz

      ! Young modulus for the solid phase
      young_s = 9.d0*kappa_s*mu_s/(3.d0*kappa_s + mu_s)

      ! Poisson's ratio for the solid phase
      poisson_s = HALF * (3.d0*kappa_s- 2.d0*mu_s)/(3.d0*kappa_s+mu_s)

      ! Poisson's ratio must be between -1 and +1/2
      if (poisson_s < -1.d0 .or. poisson_s > 0.5d0) call stop_the_code('Poisson''s ratio for the solid phase out of range')

    else if (indic <= 0) then
      ! external, tomo material (material properties will be assigned later)

      ! line format:
      !  #model_number #-1 #(val0)0 #(val1)0 #(val2)A  0 0 0 0 0 0 0 0 0 0
      assign_external_model = .true.
      tomo_material = n
      mu = val2 ! for acoustic medium vs must be 0 anyway

    else
      ! should not occur
      call exit_MPI(myrank,'wrong model flag read')
    endif

    !
    !----  set elastic coefficients and density
    !
    if (indic == ISOTROPIC_MATERIAL) then
      ! isotropic elastic/acoustic material

      density(1,n) = density_mat(1)

      poroelastcoef(1,1,n) = lambda
      poroelastcoef(2,1,n) = mu
      poroelastcoef(3,1,n) = lambdaplus2mu
      poroelastcoef(4,1,n) = compaction_grad

      QKappa_attenuationcoef(n) = QKappa
      Qmu_attenuationcoef(n) = Qmu

      if (mu > TINYVAL) then
        porosity(n) = 0.d0
      else
        porosity(n) = 1.d0
      endif

    else if (indic == ANISOTROPIC_MATERIAL) then
      ! anisotropic elastic material

      density(1,n) = density_mat(1)

      ! dummy poroelastcoef values, trick to avoid floating invalid
      poroelastcoef(1,1,n) = lambda
      poroelastcoef(2,1,n) = mu
      poroelastcoef(3,1,n) = lambdaplus2mu
      poroelastcoef(4,1,n) = ZERO  ! no compaction gradient info

      anisotropycoef(1,n) = c11
      anisotropycoef(2,n) = c13
      anisotropycoef(3,n) = c15
      anisotropycoef(4,n) = c33
      anisotropycoef(5,n) = c35
      anisotropycoef(6,n) = c55
      anisotropycoef(7,n) = c12
      anisotropycoef(8,n) = c23
      anisotropycoef(9,n) = c25
      anisotropycoef(10,n) = c22 ! This value is used for AXISYM only

      QKappa_attenuationcoef(n) = QKappa
      Qmu_attenuationcoef(n) = Qmu

      porosity(n) = 0.d0

    else if (indic == POROELASTIC_MATERIAL) then
      ! poroelastic material

      density(1,n) = density_mat(1)
      density(2,n) = density_mat(2)

      poroelastcoef(1,1,n) = lambda_s
      poroelastcoef(2,1,n) = mu_s    ! = mu_fr
      poroelastcoef(3,1,n) = lambdaplus2mu_s
      poroelastcoef(4,1,n) = ZERO

      poroelastcoef(1,2,n) = kappa_f
      poroelastcoef(2,2,n) = eta_f
      poroelastcoef(3,2,n) = ZERO
      poroelastcoef(4,2,n) = ZERO

      poroelastcoef(1,3,n) = lambda_fr
      poroelastcoef(2,3,n) = mu_fr
      poroelastcoef(3,3,n) = lambdaplus2mu_fr
      poroelastcoef(4,3,n) = ZERO

      Qmu_attenuationcoef(n) = Qmu

    else if (indic <= 0) then
      ! external, tomo material
      ! assign dummy values for now (for acoustic medium vs must be 0 anyway), these values will be read in read_external_model
      density(1,n) = -1.0d0

      poroelastcoef(1,1,n) = -1.0d0
      poroelastcoef(2,1,n) = mu
      poroelastcoef(3,1,n) = -1.0d0
      poroelastcoef(4,1,n) = ZERO

      QKappa_attenuationcoef(n) = 9999.
      Qmu_attenuationcoef(n) = 9999.

      if (mu > TINYVAL) then
        porosity(n) = 0.d0
      else
        porosity(n) = 1.d0
      endif

    else
      ! should not occur
      call exit_MPI(myrank,'wrong model flag read')
    endif

    !
    !----    check what has been read
    !
    if (myrank == 0) then
      ! user output
      if (indic == ISOTROPIC_MATERIAL) then
        ! elastic/acoustic

        ! material can be acoustic (fluid) or elastic (solid)
        if (poroelastcoef(2,1,n) > TINYVAL) then
          ! elastic
          write(IMAIN,200) n,cp,cs,density_mat(1),poisson,lambda,mu,kappa,young,QKappa,Qmu
          if (poisson < 0.d0) then
            write(IMAIN,*)
            write(IMAIN,*) 'Materials with a negative Poisson''s ratio can exist,'
            write(IMAIN,*) 'see e.g. R. Lakes, "Science" vol. 235, p. 1038-1040 (1987),'
            write(IMAIN,*) 'but are extremely rare.'
            write(IMAIN,*) 'Hope you know what you are doing...'
            write(IMAIN,*)
          endif
        else
          ! acoustic
          write(IMAIN,300) n,cp,density_mat(1),kappa,QKappa,Qmu
        endif

      else if (indic == ANISOTROPIC_MATERIAL) then
        ! elastic (anisotropic)

        if (AXISYM) then
          write(IMAIN,450) n,density_mat(1),c11,c13,c15,c33,c35,c55,c12,c23,c25,c22,Qkappa,Qmu
        else
          write(IMAIN,400) n,density_mat(1),c11,c13,c15,c33,c35,c55,c12,c23,c25,Qkappa,Qmu
        endif

      else if (indic == POROELASTIC_MATERIAL) then
        ! material is poroelastic (solid/fluid)

        write(IMAIN,500) n,sqrt(cpIsquare),sqrt(cpIIsquare),sqrt(cssquare)
        write(IMAIN,600) density_mat(1),poisson_s,lambda_s,mu_s,kappa_s,young_s
        if (poisson_s < 0.d0) then
          write(IMAIN,*)
          write(IMAIN,*) 'Materials with a negative Poisson''s ratio can exist,'
          write(IMAIN,*) 'see e.g. R. Lakes, "Science" vol. 235, p. 1038-1040 (1987),'
          write(IMAIN,*) 'but are extremely rare.'
          write(IMAIN,*) 'Hope you know what you are doing...'
          write(IMAIN,*)
        endif
        write(IMAIN,700) density_mat(2),kappa_f,eta_f
        write(IMAIN,800) lambda_fr,mu_fr,kappa_fr,porosity(n),tortuosity(n), &
                         permeability(1,n),permeability(2,n),permeability(3,n),Qmu
        write(IMAIN,900) D_biot,H_biot,C_biot,M_biot,w_c

      else if (indic <= 0) then
        ! external, tomo material

        write(IMAIN,1000) n

      endif

      write(IMAIN,*)
      call flush_IMAIN()
    endif

  enddo

  !
  !---- formats
  !
100 format(//,' M a t e r i a l   s e t s :  ', &
       ' 2 D  (p o r o) e l a s t i c i t y', &
       /1x,54('='),//5x,'Number of material sets . . . . . . (numat) =',i6)

200 format(//5x,'----------------------------------------',/5x, &
       '-- Elastic (solid) isotropic material --',/5x, &
       '----------------------------------------',/5x, &
       'Material set number. . . . . . . . (jmat) =',i6,/5x, &
       'P-wave velocity. . . . . . . . . . . (cp) =',1pe15.8,/5x, &
       'S-wave velocity. . . . . . . . . . . (cs) =',1pe15.8,/5x, &
       'Mass density. . . . . . . . . . (density) =',1pe15.8,/5x, &
       'Poisson''s ratio. . . . . . . . .(poisson) =',1pe15.8,/5x, &
       'First Lame parameter Lambda. . . (lambda) =',1pe15.8,/5x, &
       'Second Lame parameter Mu. . . . . . .(mu) =',1pe15.8,/5x, &
       'Bulk modulus Kappa . . . . . . . .(kappa) =',1pe15.8,/5x, &
       'Young''s modulus E. . . . . . . . .(young) =',1pe15.8,/5x, &
       'QKappa_attenuation .  . . . . . .(QKappa) =',1pe15.8,/5x, &
       'Qmu_attenuation . . . . . . . . . . (Qmu) =',1pe15.8)

300 format(//5x,'-------------------------------',/5x, &
       '-- Acoustic (fluid) material --',/5x, &
       '-------------------------------',/5x, &
       'Material set number. . . . . . . . (jmat) =',i6,/5x, &
       'P-wave velocity. . . . . . . . . . . (cp) =',1pe15.8,/5x, &
       'Mass density. . . . . . . . . . (density) =',1pe15.8,/5x, &
       'Bulk modulus Kappa . . . . . . . .(kappa) =',1pe15.8,/5x, &
       'QKappa_attenuation. . . . . . . .(QKappa) =',1pe15.8,/5x, &
       'Qmu_attenuation. . . . . . . . . . .(Qmu) =',1pe15.8)

400 format(//5x,'-------------------------------------',/5x, &
       '-- Anisotropic material --',/5x, &
       '-------------------------------------',/5x, &
       'Material set number. . . . . . . . (jmat) =',i6,/5x, &
       'Mass density. . . . . . . . . . (density) =',1pe15.8,/5x, &
       'c11 coefficient (Pascal). . . . . . (c11) =',1pe15.8,/5x, &
       'c13 coefficient (Pascal). . . . . . (c13) =',1pe15.8,/5x, &
       'c15 coefficient (Pascal). . . . . . (c15) =',1pe15.8,/5x, &
       'c33 coefficient (Pascal). . . . . . (c33) =',1pe15.8,/5x, &
       'c35 coefficient (Pascal). . . . . . (c35) =',1pe15.8,/5x, &
       'c55 coefficient (Pascal). . . . . . (c55) =',1pe15.8,/5x, &
       'c12 coefficient (Pascal). . . . . . (c12) =',1pe15.8,/5x, &
       'c23 coefficient (Pascal). . . . . . (c23) =',1pe15.8,/5x, &
       'c25 coefficient (Pascal). . . . . . (c25) =',1pe15.8,/5x, &
       'QKappa_attenuation. . . . . . . .(QKappa) =',1pe15.8,/5x, &
       'Qmu_attenuation. . . . . . . . . . .(Qmu) =',1pe15.8)

450 format(//5x,'-------------------------------------',/5x, &
       '-- Axisymetrical anisotropic material --',/5x, &
       '-------------------------------------',/5x, &
       'Material set number. . . . . . . . (jmat) =',i6,/5x, &
       'Mass density. . . . . . . . . . (density) =',1pe15.8,/5x, &
       'c11 coefficient (Pascal). . . . . . (c11) =',1pe15.8,/5x, &
       'c13 coefficient (Pascal). . . . . . (c13) =',1pe15.8,/5x, &
       'c15 coefficient (Pascal). . . . . . (c15) =',1pe15.8,/5x, &
       'c33 coefficient (Pascal). . . . . . (c33) =',1pe15.8,/5x, &
       'c35 coefficient (Pascal). . . . . . (c35) =',1pe15.8,/5x, &
       'c55 coefficient (Pascal). . . . . . (c55) =',1pe15.8,/5x, &
       'c12 coefficient (Pascal). . . . . . (c12) =',1pe15.8,/5x, &
       'c23 coefficient (Pascal). . . . . . (c23) =',1pe15.8,/5x, &
       'c25 coefficient (Pascal). . . . . . (c25) =',1pe15.8,/5x, &
       'c22 coefficient (Pascal). . . . . . (c22) =',1pe15.8,/5x, &
       'QKappa_attenuation. . . . . . . .(QKappa) =',1pe15.8,/5x, &
       'Qmu_attenuation. . . . . . . . . . .(Qmu) =',1pe15.8)

500 format(//5x,'----------------------------------------',/5x, &
       '-- Poroelastic isotropic material --',/5x, &
       '----------------------------------------',/5x, &
       'Material set number. . . . . . . . (jmat) =',i6,/5x, &
       'First P-wave velocity. . . . . . . .(cpI) =',1pe15.8,/5x, &
       'Second P-wave velocity. . . . . . .(cpII) =',1pe15.8,/5x, &
       'S-wave velocity. . . . . . . . . . . (cs) =',1pe15.8)

600 format(//5x,'-------------------------------',/5x, &
       '-- Solid phase properties --',/5x, &
       'Mass density. . . . . . . . . . (density_s) =',1pe15.8,/5x, &
       'Poisson''s ratio . . . . . . . . (poisson_s) =',1pe15.8,/5x, &
       'First Lame parameter Lambda. . . (lambda_s) =',1pe15.8,/5x, &
       'Second Lame parameter Mu. . . . . . .(mu_s) =',1pe15.8,/5x, &
       'Solid bulk modulus Kappa . . . . .(kappa_s) =',1pe15.8,/5x, &
       'Young''s modulus E . . . . . . .  .(young_s) =',1pe15.8)

700 format(//5x,'-------------------------------',/5x, &
       '-- Fluid phase properties --',/5x, &
       'Mass density. . . . . . . . . . (density_f) =',1pe15.8,/5x, &
       'Fluid bulk modulus Kappa . . . . .(kappa_f) =',1pe15.8,/5x, &
       'Fluid viscosity Eta . . . . . . . . (eta_f) =',1pe15.8)

800 format(//5x,'-------------------------------',/5x, &
       '-- Frame properties --',/5x, &
       'First Lame parameter Lambda. . . (lambda_fr) =',1pe15.8,/5x, &
       'Second Lame parameter Mu. . . . . . .(mu_fr) =',1pe15.8,/5x, &
       'Frame bulk modulus Kappa . . . . .(kappa_fr) =',1pe15.8,/5x, &
       'Porosity. . . . . . . . . . . . . . . .(phi) =',1pe15.8,/5x, &
       'Tortuosity. . . . . . . . . . . . . . . .(c) =',1pe15.8,/5x, &
       'Permeability xx component. . . . . . . . . . =',1pe15.8,/5x, &
       'Permeability zx component. . . . . . . . . . =',1pe15.8,/5x, &
       'Permeability zz component. . . . . . . . . . =',1pe15.8,/5x, &
       'Qmu_attenuation. . . . . . . . . . . . (Qmu) =',1pe15.8)

900 format(//5x,'-------------------------------',/5x, &
         '-- Biot coefficients --',/5x, &
         '-------------------------------',/5x, &
         'D. . . . . . . . . .=',1pe15.8,/5x, &
         'H. . . . . . . . . .=',1pe15.8,/5x, &
         'C. . . . . . . . . .=',1pe15.8,/5x, &
         'M. . . . . . . . . .=',1pe15.8,/5x, &
         'Characteristic freq =',1pe15.8)

1000 format(//5x,'----------------------------------------------------',/5x, &
       '-- Material described by external tomography file --',/5x, &
       '----------------------------------------------------',/5x, &
       'Material set number. . . . . . . . (jmat) =',i6,/5x)

  end subroutine read_materials

