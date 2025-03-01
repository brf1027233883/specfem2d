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

!*************************************************************
! NOISE TOMOGRAPHY TO DO LIST
!
! 1. Use separate STATIONS_ADJOINT file
! 2. Add exploration test case under EXAMPLES
! 3. Update manual
!*************************************************************


  subroutine create_mask_noise()

! specify spatial distribution of microseismic noise sources

! **** USERS can modify this subroutine **** to suit their own needs

  use constants, only: IIN,IMAIN,MAX_STRING_LEN,myrank

  implicit none

  ! local parameters
  logical :: file_exists
  integer :: noise_distribution_type,ier
  character(len=MAX_STRING_LEN) :: filename

  ! parameter helps choosing between different noise distributions
  ! users can add their own mask implementation...
  ! (default is a uniform distribution)
  integer :: NOISE_DIST_TYPE

  ! initializes, by default uniform noise
  ! (0 == uniform / 1 == non-uniform noise distribution routine will be used)
  NOISE_DIST_TYPE = 0

  ! check if non-uniform noise distribution should be used
  ! takes value specified in additional file NOISE_TOMOGRAPHY/use_non_uniform_noise_distribution
  filename = 'NOISE_TOMOGRAPHY/use_non_uniform_noise_distribution'
  inquire(file=trim(filename), exist=file_exists)
  if (file_exists) then
    open(unit=IIN,file=trim(filename),status='old',action='read',iostat=ier)
    if (ier == 0) then
      ! read in flag
      read(IIN,*) noise_distribution_type
      close(IIN)

      ! user output
      if (myrank == 0) then
        write(IMAIN,*) '  noise distribution: found file ',trim(filename)
        write(IMAIN,*) '                      read noise_distribution_type = ',noise_distribution_type
      endif

      ! sets distribution type
      NOISE_DIST_TYPE = noise_distribution_type
    endif
  endif

  ! chooses noise distribution
  select case (NOISE_DIST_TYPE)
  case (0)
    ! uniform noise distribution
    if (myrank == 0) write(IMAIN,*) '  noise distribution: using uniform distribution'
    call create_mask_noise_uniform()
  case (1)
    ! non-uniform noise distribution
    if (myrank == 0) write(IMAIN,*) '  noise distribution: using non-uniform distribution'
    call create_mask_noise_nonuniform()
  case default
    ! default is uniform distribution
    if (myrank == 0) write(IMAIN,*) '  noise distribution: using uniform distribution'
    call create_mask_noise_uniform()
  end select

  end subroutine create_mask_noise

!
!========================================================================
!

  subroutine create_mask_noise_uniform()

! uniform noise distribution

  use constants, only: CUSTOM_REAL
  use specfem_par, only: nglob,coord
  use specfem_par_noise, only: mask_noise

  implicit none

  !local
  integer :: iglob
  real(kind=CUSTOM_REAL) :: xx,zz

  !specify distribution of noise sources as a function of xx, zz
  do iglob = 1,nglob
    xx = coord(1,iglob)
    zz = coord(2,iglob)

    !below, the noise is assumed to be uniform; users are free to
    !to change this expression to one involving xx, zz
    mask_noise(iglob) = 1.0

  enddo

  end subroutine create_mask_noise_uniform

!
!========================================================================
!

  subroutine create_mask_noise_nonuniform()

! example for a non-uniform noise distribution

  use constants, only: CUSTOM_REAL,PI
  use specfem_par, only: nglob,coord
  use specfem_par_noise, only: mask_noise

  implicit none

  !local
  integer :: iglob
  real(kind=CUSTOM_REAL) :: xx,zz,aa,phi

  real(kind=CUSTOM_REAL),parameter :: POS_X = 105.e3
  real(kind=CUSTOM_REAL),parameter :: POS_Z = 92.e3

  real(kind=CUSTOM_REAL),parameter :: RAD_X = 28.e3
  real(kind=CUSTOM_REAL),parameter :: RAD_Z = 20.e3

  aa = PI/8.0

  ! specify distribution of noise sources as a function of xx, zz
  do iglob = 1,nglob
    xx = coord(1,iglob)
    zz = coord(2,iglob)

    ! distance function
    phi = (((xx-POS_X)*cos(aa)+(zz-POS_Z)*sin(aa))/RAD_X)**2 + &
          (((xx-POS_X)*sin(aa)-(zz-POS_Z)*cos(aa))/RAD_Z)**2

    ! weighting
    if (phi < 0.9) then
        mask_noise(iglob) = 1.0_CUSTOM_REAL
    else if (phi < 1.1) then
        mask_noise(iglob) = 0.5*(1.0 + cos(5.0*PI*(phi/1.1 - 0.8)))
    else
        mask_noise(iglob) = 0.0_CUSTOM_REAL
    endif
  enddo

  end subroutine create_mask_noise_nonuniform

!
!========================================================================
!

  subroutine read_parameters_noise()

! read noise parameters and check for consistency

  use constants, only: IIN,IMAIN,PI,NOISE_MOVIE_OUTPUT,NOISE_SAVE_EVERYWHERE

  use shared_parameters, only: noise_source_time_function_type

  use specfem_par, only: myrank,SIMULATION_TYPE,SAVE_FORWARD,NOISE_TOMOGRAPHY, &
                         any_acoustic,any_poroelastic,P_SV, &
                         xi_receiver,gamma_receiver, &
                         ispec_selected_rec,islice_selected_rec,nrec, &
                         station_name,network_name

  use specfem_par_noise

  implicit none

  ! local parameters
  integer :: ier

  ! main noise source angle (in rad) use for P_SV-case: 0 for vertical along z-direction
  angle_noise = 0._CUSTOM_REAL

  ! define main receiver
  open(unit=IIN,file='NOISE_TOMOGRAPHY/irec_main_noise',status='old',action='read',iostat=ier)
  if (ier /= 0) then
    ! we will be strict on input format
    print *
    write(*,*) 'Error opening NOISE_TOMOGRAPHY/irec_main_noise file'
    write(*,*) 'Please make sure all noise setup files exist in NOISE_TOMOGRAPHY/ directory...'
    print *
    call stop_the_code('Error opening NOISE_TOMOGRAPHY/irec_main_noise file')
  endif

  read(IIN,*) irec_main_noise
  close(IIN)

  ! user output
  if (myrank == 0) then
    write(IMAIN,*) '  noise simulation type           = ',NOISE_TOMOGRAPHY
    write(IMAIN,*) '  noise source time function type = ',noise_source_time_function_type
    write(IMAIN,*)
    write(IMAIN,*) '  main station is #',irec_main_noise,': ',trim(network_name(irec_main_noise))&
      //'.'//trim(station_name(irec_main_noise))

    if (P_SV) then
      write(IMAIN,*) '  using P_SV waves'
      write(IMAIN,*) '  angle of the noise source is ',angle_noise * 180./PI,'degrees (0=vertical)'
    else
      write(IMAIN,*) '  using SH waves'
    endif
    if (NOISE_MOVIE_OUTPUT) write(IMAIN,*) '  outputting noise movie snapshot files'
    if (NOISE_SAVE_EVERYWHERE) write(IMAIN,*) '  saving noise field for reconstruction'
    write(IMAIN,*)
    call flush_IMAIN()
  endif

  ! check simulation parameters
  if ((NOISE_TOMOGRAPHY /= 0) .and. (P_SV)) write(*,*) 'Warning: For P-SV case, noise tomography subroutines not yet fully tested'

  if (NOISE_TOMOGRAPHY == 1) then
     if (SIMULATION_TYPE /= 1) call exit_MPI(myrank,'NOISE_TOMOGRAPHY=1 requires SIMULATION_TYPE=1, check DATA/Par_file')

  else if (NOISE_TOMOGRAPHY == 2) then
     if (SIMULATION_TYPE /= 1) call exit_MPI(myrank,'NOISE_TOMOGRAPHY=2 requires SIMULATION_TYPE=1, check DATA/Par_file')
     if (.not. SAVE_FORWARD) call exit_MPI(myrank,'NOISE_TOMOGRAPHY=2 requires SAVE_FORWARD=.true., check DATA/Par_file')

  else if (NOISE_TOMOGRAPHY == 3) then
     if (SIMULATION_TYPE /= 3) call exit_MPI(myrank,'NOISE_TOMOGRAPHY=3 requires SIMULATION_TYPE=3, check DATA/Par_file')
     if (SAVE_FORWARD)       call exit_MPI(myrank,'NOISE_TOMOGRAPHY=3 requires SAVE_FORWARD=.false., check DATA/Par_file')
  endif

  ! check model parameters
  if (any_acoustic) &
    call exit_MPI(myrank,'Acoustic models not yet implemented for noise simulations. Exiting.')
  if (any_poroelastic) &
    call exit_MPI(myrank,'Poroelastic models not yet implemented for noise simulations. Exiting.')

  ! note that moment tensor source elements specified in file DATA/SOURCE will be ignored for noise simulations

  xi_noise    = xi_receiver(irec_main_noise)
  gamma_noise = gamma_receiver(irec_main_noise)
  ispec_noise = ispec_selected_rec(irec_main_noise)

  if (NOISE_TOMOGRAPHY == 1) then
    ! checks value
    if (irec_main_noise > nrec .or. irec_main_noise < 1) &
      call exit_MPI(myrank,'irec_main_noise out of range of given number of receivers. Exiting.')

    ! creates generating noise source
    if (myrank == islice_selected_rec(irec_main_noise)) then
      call compute_arrays_source_noise()
    endif
  endif

  ! sets up noise distribution and noise direction
  call create_mask_noise()

  end subroutine read_parameters_noise

!
!========================================================================
!

  subroutine compute_arrays_source_noise()

! reads in time series based on noise spectrum and construct noise "source" array

! ---------------------------------------------------------------------------------
! A note about time functions for noise simulations
!
! In noise forward modeling and inversion, "time function" is used to refer
! to the source time function that drives the first noise simulation.
!
! Typically, the time function must be computed based on the frequency
! characterstics of the desired noise sources. For example, if you wanted to
! generate synthetic correlograms representative of the noise field in a
! particular geographic region, you would have to use a time function created
! by inverse Fourier transforming a model of the noise spectrum for that
! region.
!
! FOR A REALISTIC MODEL OF THE SEISMIC NOISE FIELD,
! THE VARIABE "noise_source_time_function_type" (SET IN setup/constants.h) SHOULD BE SET TO 0
! AND A TIME function FOR THE DESIRED NOISE SPECTRUM SHOULD BE
! ***SUPPLIED BY THE USER*** IN THE FILE "NOISE_TOMOGRAPHY/S_squared"
!
! The alternative--setting "time_function_type" to a value other than
! 0--results in an idealized time function that does not represent a physically
! realizable noise spectrum but which nevertheless may be useful for
! performing tests or illustrating certain theoretical concepts.
!
! ----------------------------------------------------------------------------------

  use constants, only: CUSTOM_REAL,NGLLX,NGLLZ,NGLJ,IIN,IOUT,IMAIN,OUTPUT_FILES

  use shared_parameters, only: noise_source_time_function_type

  use specfem_par, only: AXISYM,is_on_the_axis,xiglj,P_SV,NSTEP,DT, &
                         xigll,zigll,myrank

  use specfem_par_noise

  implicit none

  !local
  integer :: it,i,j,ier,nlines
  real(kind=CUSTOM_REAL) :: t,t0,junk
  double precision, dimension(NGLLX) :: hxi, hpxi
  double precision, dimension(NGLLZ) :: hgamma, hpgamma
  real(kind=CUSTOM_REAL), dimension(NSTEP) :: noise_src

  ! parameters for Gaussian/Ricker type source time functions
  real(kind=CUSTOM_REAL),parameter :: a_val = 0.6_CUSTOM_REAL, factor_noise = 1.e3_CUSTOM_REAL

  ! initializes
  noise_src(:) = 0._CUSTOM_REAL

  ! noise simulations use cross-correlation wavefields, with duration between [-T,T]
  ! mid-time becomes zero time t0
  t0 = ((NSTEP-1)/2.0_CUSTOM_REAL) * DT

  if (myrank == 0) then
    write(IMAIN,*) '  noise source array:'
    write(IMAIN,*) '  number of time steps = ',NSTEP
    write(IMAIN,*) '  zero-time t0         = ',t0
  endif

  if (noise_source_time_function_type == 0) then
    !read in time function from file S_squared
    ! user output
    if (myrank == 0) then
      write(IMAIN,*) '  reading noise source from file ','NOISE_TOMOGRAPHY/S_squared'
    endif
    open(unit=IIN,file='NOISE_TOMOGRAPHY/S_squared',status='old',iostat=ier)
    if (ier /= 0) call stop_the_code('Error opening file NOISE_TOMOGRAPHY/S_squared')

    ! counts line reads noise source S(t)
    nlines = 0
    do while(ier == 0)
      read(IIN,*,iostat=ier) junk, junk
      if (ier == 0)  nlines = nlines + 1
    enddo
    rewind(IIN)

    ! user output
    if (myrank == 0) then
      write(IMAIN,*) '  number of lines      = ',nlines
    endif

    ! checks to be sure that file is matching simulation setup
    if (nlines /= NSTEP) then
      print *,'Error: invalid number of lines ',nlines,' in file NOISE_TOMOGRAPHY/S_squared'
      print *,'       must match simulation steps NSTEP = ',NSTEP
      print *,'Please check file S_squared and NSTEP in Par_file'
      call exit_MPI(myrank,'Invalid number of lines in file S_squared')
    endif

    ! actual read in noise stf
    do it = 1,NSTEP
      ! format: #time #Source-time-function-value
      read(IIN,*,iostat=ier) junk,noise_src(it)
      if (ier /= 0) then
        print *,'Error reading file S_squared'
        stop 'Invalid S_squared file'
      endif
    enddo
    close(IIN)

    ! user output
    if (myrank == 0) then
      write(IMAIN,*) '  noise source S_squared: min/max = ',minval(noise_src(:)),'/',maxval(noise_src(:))
    endif

    ! normalizes
    if (maxval(abs(noise_src)) > 1.e-30_CUSTOM_REAL) then
      noise_src(:) = noise_src(:)/maxval(abs(noise_src))
    else
      print *,'Error: noise source S_squared is (almost) zero: absolute max = ',maxval(abs(noise_src))
      print *,'Please check source file NOISE_TOMOGRAPHY/S_squared'
      stop 'Error source S_squared zero'
    endif

    ! user output
    if (myrank == 0) then
      write(IMAIN,*) '  noise source S_squared normalized: min/max = ',minval(noise_src(:)),maxval(noise_src(:))
      call flush_IMAIN()
    endif

  else if (noise_source_time_function_type == 1) then
    !Ricker (second derivative of a Gaussian) time function
    ! user output
    if (myrank == 0) then
      write(IMAIN,*) '  Ricker (second derivative) noise source'
    endif
    do it = 1,NSTEP
      t = it * DT
      noise_src(it) = - factor_noise * 2.0 * a_val * (1.0 - 2.0 * a_val * (t-t0)**2) * exp(-a_val * (t-t0)**2)
    enddo

  else if (noise_source_time_function_type == 2) then
    !first derivative of a Gaussian time function
    ! user output
    if (myrank == 0) then
      write(IMAIN,*) '  Ricker (first derivative) noise source'
    endif
    do it = 1,NSTEP
      t = it * DT
      noise_src(it) = - factor_noise * (2.0 * a_val * (t-t0)) * exp(-a_val * (t-t0)**2)
    enddo

  else if (noise_source_time_function_type == 3) then
    !Gaussian time function
    ! user output
    if (myrank == 0) then
      write(IMAIN,*) '  Gaussian noise source'
    endif
    do it = 1,NSTEP
      t = it * DT
      noise_src(it) = factor_noise * exp(-a_val * (t-t0)**2)
    enddo

  else if (noise_source_time_function_type == 4) then
    !reproduce time function from Figure 2a of Tromp et al. 2010
    ! user output
    if (myrank == 0) then
      write(IMAIN,*) '  Figure 2a noise source'
    endif
    do it = 1,NSTEP
      t = it * DT
      noise_src(it) = factor_noise * 4.0 * a_val**2 * (3.0 - 12.0 * a_val * (t-t0)**2 + 4.0 * a_val**2 * (t-t0)**4) * &
                      exp(-a_val * (t-t0)**2)
    enddo

  else
    call exit_MPI(myrank,'Bad noise_source_time_function_type in compute_arrays_source_noise. Please check setting in constants.h')
  endif

  ! saves source time function
  open(IOUT,file=trim(OUTPUT_FILES)//'plot_source_time_function_noise.txt',status='unknown',iostat=ier)
  if (ier /= 0) call stop_the_code('Error opening noise source time function text-file')
  do it = 1,NSTEP
    t = it * DT
    write(IOUT,*) (t-t0),noise_src(it)
  enddo
  close(IOUT)

  ! interpolates over GLL points
  if (AXISYM) then
    if (is_on_the_axis(ispec_noise)) then
      call lagrange_any(xi_noise,NGLJ,xiglj,hxi,hpxi)
    else
      call lagrange_any(xi_noise,NGLLX,xigll,hxi,hpxi)
    endif
  else
    call lagrange_any(xi_noise,NGLLX,xigll,hxi,hpxi)
  endif

  call lagrange_any(gamma_noise,NGLLZ,zigll,hgamma,hpgamma)

  ! main station for noise source: located in element ispec_noise
  noise_sourcearray(:,:,:,:) = 0._CUSTOM_REAL
  if (P_SV) then
    ! P-SV simulation
    do j = 1,NGLLZ
      do i = 1,NGLLX
        ! iglob = ibool(i,j,ispec_noise)
        noise_sourcearray(1,i,j,:) = noise_src(:) * hxi(i) * hgamma(j)
        noise_sourcearray(2,i,j,:) = noise_src(:) * hxi(i) * hgamma(j)
      enddo
    enddo
  else
    ! SH (membrane) simulation
    do j = 1,NGLLZ
      do i = 1,NGLLX
        ! iglob = ibool(i,j,ispec_noise)
        noise_sourcearray(1,i,j,:) = noise_src(:) * hxi(i) * hgamma(j)
      enddo
    enddo
  endif

  end subroutine compute_arrays_source_noise

!
!========================================================================
!

  subroutine add_point_source_noise()

! inject the "source" that drives the "generating wavefield"

  use constants, only: NGLLX,NGLLZ

  use specfem_par, only: P_SV,it,ibool,accel_elastic,islice_selected_rec,myrank

  use specfem_par_noise, only: ispec_noise,angle_noise,noise_sourcearray,irec_main_noise

  implicit none

  ! local parameters
  integer :: i,j,iglob

  ! only add source in the slice where the main receiver is located
  if (myrank .ne. islice_selected_rec(irec_main_noise)) then
    return
  endif

  if (P_SV) then
    ! P-SV calculation
    do j = 1,NGLLZ
      do i = 1,NGLLX
        iglob = ibool(i,j,ispec_noise)
        accel_elastic(1,iglob) = accel_elastic(1,iglob) + sin(angle_noise)*noise_sourcearray(1,i,j,it)
        accel_elastic(2,iglob) = accel_elastic(2,iglob) - cos(angle_noise)*noise_sourcearray(2,i,j,it)
      enddo
    enddo
  else
    ! SH (membrane) calculation
    do j = 1,NGLLZ
      do i = 1,NGLLX
        iglob = ibool(i,j,ispec_noise)
        accel_elastic(1,iglob) = accel_elastic(1,iglob) - noise_sourcearray(1,i,j,it)
      enddo
    enddo
  endif

  end subroutine add_point_source_noise

!
!========================================================================
!

  subroutine noise_save_movie_output()

! noise simulations saves wavefield snapshots for movies, only in kernel simulation
  use constants, only: CUSTOM_REAL,OUTPUT_FILES,MAX_STRING_LEN

  use specfem_par, only: myrank,it,NOISE_TOMOGRAPHY,GPU_MODE, &
    ibool,nglob,nspec, &
    accel_elastic,b_displ_elastic, &
    rho_kl

  use specfem_par_noise, only: mask_noise, &
    noise_surface_movie_y_or_z,noise_output_rhokl,noise_output_array,noise_output_ncol, &
    noise_output_rhokl

  implicit none
  ! local parameters
  integer :: iglob,ier
  logical :: ex,is_opened
  real(kind=CUSTOM_REAL) :: rho_k_loc
  character(len=MAX_STRING_LEN) :: noise_output_file,noise_input_file

  ! checks if anything to do
  if (NOISE_TOMOGRAPHY /= 3) return

  if (.not. GPU_MODE) then
    ! load ensemble forward source
    inquire(unit=501,exist=ex,opened=is_opened)
    if (.not. is_opened) then
      write(noise_input_file,'(a,i6.6,a)') 'noise_eta',myrank,'.bin'
      open(unit=501,file=trim(OUTPUT_FILES)//noise_input_file,access='direct', &
           recl=nglob*CUSTOM_REAL,action='read',iostat=ier)
      if (ier /= 0) call exit_MPI(myrank,'Error opening noise eta file')
    endif
    ! for both P_SV/SH cases
    read(unit=501,rec=it) noise_surface_movie_y_or_z ! either y (SH) or z (P_SV) component

    ! load product of fwd, adj wavefields
    call spec2glob(nspec,nglob,ibool,rho_kl,noise_output_rhokl)

    ! prepares array
    ! noise distribution
    noise_output_array(1,:) = noise_surface_movie_y_or_z(:) * mask_noise(:)

    ! P_SV/SH-case
    noise_output_array(2,:) = b_displ_elastic(1,:)
    noise_output_array(3,:) = accel_elastic(1,:)

    ! rho kernel contribution on global nodes
    do iglob = 1,nglob
      rho_k_loc =  accel_elastic(1,iglob)*b_displ_elastic(1,iglob) + accel_elastic(2,iglob)*b_displ_elastic(2,iglob)
      noise_output_array(4,iglob) = rho_k_loc
    enddo

    ! rho kernel on global nodes from local kernel (for comparison)
    noise_output_array(5,:) = noise_output_rhokl(:)

    ! writes out to text file
    write(noise_output_file,"(a,i6.6,a)") trim(OUTPUT_FILES)//'noise_snapshot_all_',it,'.txt'
    call snapshots_noise(noise_output_ncol,nglob,noise_output_file,noise_output_array)

    ! re-initializes noise array
    noise_surface_movie_y_or_z(:) = 0._CUSTOM_REAL
  endif

  end subroutine noise_save_movie_output

!
!========================================================================
!

  subroutine add_surface_movie_noise(accel_elastic)

! read in and inject the "source" that drives the "ensemble forward wavefield"
! (recall that the ensemble forward wavefield has a spatially distributed source)

  use constants, only: CUSTOM_REAL,NGLLX,NGLLZ,NDIM,NOISE_SAVE_EVERYWHERE,&
    OUTPUT_FILES,MAX_STRING_LEN

  use specfem_par, only: P_SV,it,NSTEP,nspec,nglob,ibool,jacobian,wxgll,wzgll,myrank,NOISE_TOMOGRAPHY

  use specfem_par_noise

  implicit none

  real(kind=CUSTOM_REAL), dimension(NDIM,nglob) :: accel_elastic

  !local
  integer :: ier, i, j, ispec, iglob
  character(len=MAX_STRING_LEN) :: noise_input_file

  ! checks if anything to do
  if (NOISE_TOMOGRAPHY /= 2 .and. NOISE_TOMOGRAPHY /= 3) return

  ! checks if reconstruction by file storage
  if (NOISE_TOMOGRAPHY == 3 .and. NOISE_SAVE_EVERYWHERE) return

  ! opens noise source file
  if (it == 1) then
    write(noise_input_file,'(a,i6.6,a)') 'noise_eta',myrank,'.bin'
    open(unit=501,file=trim(OUTPUT_FILES)//noise_input_file,access='direct', &
         recl=nglob*CUSTOM_REAL,action='read',iostat=ier)
    if (ier /= 0) call exit_MPI(myrank,'Error retrieving generating wavefield.')
  endif

  ! generating wavefield
  if (NOISE_TOMOGRAPHY == 2) then
    ! reads backward
    ! for both SH- or P-SV calculation (only vertical component as noise for now...)
    read(unit=501,rec=NSTEP-it+1) noise_surface_movie_y_or_z
  else if (NOISE_TOMOGRAPHY == 3) then
    ! for reconstructed/backward wavefield
    ! reads forward again
    ! for both SH- or P-SV calculation (only vertical component...)
    read(unit=501,rec=it) noise_surface_movie_y_or_z
  endif

  ! close file at simulation end
  if (it == NSTEP) then
    close(501)
  endif

  do ispec = 1, nspec
    do j = 1, NGLLZ
      do i = 1, NGLLX
        iglob = ibool(i,j,ispec)
        if (P_SV) then
          ! P-SV calculation
          !accel_elastic(1,iglob) = accel_elastic(1,iglob) + surface_movie_x_noise(iglob) * &
          !                         mask_noise(iglob) * wxgll(i)*wzgll(j)*jacobian(i,j,ispec)
          ! only vertical for now...
          accel_elastic(2,iglob) = accel_elastic(2,iglob) + noise_surface_movie_y_or_z(iglob) * &
                                   mask_noise(iglob) * wxgll(i)*wzgll(j)*jacobian(i,j,ispec)

        else
          ! SH (membrane) calculation
          accel_elastic(1,iglob) = accel_elastic(1,iglob) + noise_surface_movie_y_or_z(iglob) * &
                                   mask_noise(iglob) * wxgll(i)*wzgll(j)*jacobian(i,j,ispec)
        endif
      enddo
    enddo
  enddo

  end subroutine add_surface_movie_noise

!
!========================================================================
!

  subroutine noise_save_surface_movie()

! first step of noise tomography, i.e., save a surface movie at every time step
!
! step 1: calculate the "ensemble forward source", save surface movie (displacement) at every time steps, for step 2 & 3.
!
! save a snapshot of the "generating wavefield" eta that will be used to drive
! the "ensemble forward wavefield"

  use constants, only: CUSTOM_REAL,NDIM,IMAIN,OUTPUT_FILES,MAX_STRING_LEN

  use specfem_par, only: myrank,it,NSTEP,nglob,P_SV, &
    displ_elastic,veloc_elastic,accel_elastic, &
    nglob_elastic,NOISE_TOMOGRAPHY, &
    any_elastic,GPU_MODE

  use specfem_par_gpu, only: Mesh_pointer,NGLOB_AB

  implicit none

  ! local parameter
  integer :: ier
  real(kind=CUSTOM_REAL), dimension(nglob) :: wavefield
  character(len=MAX_STRING_LEN) :: noise_output_file

  ! checks if anything to do
  if (NOISE_TOMOGRAPHY /= 1 .and. NOISE_TOMOGRAPHY /= 2) return

  ! safety check
  if (nglob /= nglob_elastic) &
    call stop_the_code('Noise simulation requires elastic simulation')

  ! transfers arrays from GPU to CPU
  if (GPU_MODE) then
    ! elastic domains
    if (any_elastic) then
      call transfer_fields_el_from_device(NDIM*NGLOB_AB,displ_elastic,veloc_elastic,accel_elastic,Mesh_pointer)
    endif
  endif

  if (NOISE_TOMOGRAPHY == 1) then
    ! stores forward generating wavefield

    ! opens files
    if (it == 1) then
      ! user output
      if (myrank == 0) write(IMAIN,*) 'noise simulation: storing generating wavefield in file noise_eta.bin'

      ! opens file
      write(noise_output_file,'(a,i6.6,a)') 'noise_eta',myrank,'.bin'
      open(unit=501,file=trim(OUTPUT_FILES)//noise_output_file,access='direct', &
           recl=nglob*CUSTOM_REAL,action='write',iostat=ier)
      if (ier /= 0) call exit_MPI(myrank,'Error saving generating wavefield.')
    endif

    ! stores generating wavefield
    if (P_SV) then
      ! P_SV-case
      wavefield(:) = displ_elastic(2,:) ! only vertical component
    else
      ! SH-case
      wavefield(:) = displ_elastic(1,:)
    endif

    ! file output
    write(unit=501,rec=it) wavefield

    ! closes file at the end of simulation
    if (it == NSTEP) then
      close(501)
    endif

  else if (NOISE_TOMOGRAPHY == 2) then
    ! stores whole forward wavefield for reconstruction

    ! opens files
    if (it == 1) then
      ! user output
      if (myrank == 0) write(IMAIN,*) 'noise simulation: storing forward wavefield in file noise_phi.bin'

      ! opens file
      write(noise_output_file,'(a,i6.6,a)') 'noise_phi',myrank,'.bin'
      open(unit=502,file=trim(OUTPUT_FILES)//noise_output_file,access='direct', &
           recl=NDIM*nglob*CUSTOM_REAL,action='write',iostat=ier)
      if (ier /= 0) call exit_MPI(myrank,'Error saving ensemble forward wavefield.')
    endif

    ! stores complete wavefield
    write(unit=502,rec=it) displ_elastic  ! full array, avoids temporary copies when using: displ_elastic(1,:),displ_elastic(2,:)

    ! closes file at the end of simulation
    if (it == NSTEP) then
      close(502)
    endif

  endif

  end subroutine noise_save_surface_movie

!
!========================================================================
!

  subroutine noise_read_wavefield()

! reads in backward wavefield

  use constants, only: CUSTOM_REAL,NDIM,OUTPUT_FILES,MAX_STRING_LEN

  use specfem_par, only: myrank,it,NSTEP,nglob,b_displ_elastic,NOISE_TOMOGRAPHY

  implicit none
  ! local parameters
  integer :: ier
  character(len=MAX_STRING_LEN) :: noise_input_file

  ! checks if anything to do
  if (NOISE_TOMOGRAPHY /= 3) return

  ! opens noise file
  if (it == 1) then
    write(noise_input_file,'(a,i6.6,a)') 'noise_phi',myrank,'.bin'
    open(unit=503,file=trim(OUTPUT_FILES)//noise_input_file,access='direct', &
         recl=NDIM*nglob*CUSTOM_REAL,action='read',iostat=ier)
    if (ier /= 0) call exit_MPI(myrank,'Error retrieving noise ensemble forward wavefield')
  endif

  ! reads stored wavefield for reconstructed/backward wavefield
  read(unit=503,rec=NSTEP-it+1) b_displ_elastic  ! full array, avoids temporary copies

  ! closes file
  if (it == NSTEP) then
    close(503)
  endif

  end subroutine noise_read_wavefield

!
!========================================================================
!

  subroutine snapshots_noise(ncol,nglob,filename,array_all)

  use constants, only: CUSTOM_REAL,MAX_STRING_LEN

  implicit none

  !input paramters
  integer :: ncol,nglob
  character(len=MAX_STRING_LEN) :: filename

  real(kind=CUSTOM_REAL), dimension(ncol,nglob) :: array_all

  !local parameters
  integer :: i,iglob

  open(unit=504,file=filename,status='unknown',action='write')

  do iglob = 1,nglob
    do i = 1,ncol-1
      write(unit=504,fmt='(1pe12.3e3)',advance='no') array_all(i,iglob)
    enddo
    write(unit=504,fmt='(1pe13.3e3)') array_all(ncol,iglob)
  enddo

  close(504)

  end subroutine snapshots_noise

!
!========================================================================
!

! auxillary routine

  subroutine spec2glob(nspec,nglob,ibool,array_spec,array_glob)

! converts local basis array(i,j,ispec) to global array(iglob)

  use constants, only: CUSTOM_REAL,NGLLX,NGLLZ

  implicit none

  !input
  integer :: nspec, nglob
  integer :: ibool(NGLLX,NGLLZ,nspec)

  real(kind=CUSTOM_REAL), dimension(nglob) :: array_glob
  real(kind=CUSTOM_REAL), dimension(NGLLX,NGLLZ,nspec) :: array_spec

  !local
  integer :: i,j,iglob,ispec

  do ispec = 1, nspec
    do j = 1, NGLLZ
      do i = 1, NGLLX
        iglob = ibool(i,j,ispec)
        array_glob(iglob) = array_spec(i,j,ispec)
     enddo
    enddo
  enddo

  end subroutine spec2glob

