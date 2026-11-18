! Build with make MPI=1 ibm-force-balance. Run build-gfortran-mpi1/ibm_force_balance
! from a small fixed-cylinder case directory with inFlow.dat and its body mesh.
program ibm_force_balance
    use ConstParams, only: pi
    use FlowCondition, only: flow, read_flow_conditions
    use SolidBody
    use FluidDomain
    use LBMBlockComm, only: build_block_tree, blockTreeRoot
    use ParallelDomain, only: start_parallel, finish_parallel, max_values, sum_values, parallel_abort, is_root
    implicit none
    character(40) :: filename = 'inFlow.dat'
    real(8) :: gravity(3) = 0.d0, initial(3) = [0.08d0, 0.016d0, -0.004d0]
    real(8) :: fluid_load(3), body_load(3), metrics(2), balance_error
    integer :: component, x, z, trial

    call start_parallel()
    call read_flow_conditions(filename)
    call read_solid_files(filename, gravity)
    call read_fuild_blocks(filename)
    call build_block_tree()
    call allocate_solid_memory(flow%Asfac, flow%Lchod, flow%Lspan, flow%AR)
    call calculate_reference_params(flow)
    call set_solidbody_parameters(flow%denIn,flow%uvwIn,LBMblks(blockTreeRoot)%BndConds, &
        flow%Aref,flow%Eref,flow%Fref,flow%Lref,flow%Pref,flow%Tref,flow%Uref,1,0.d0)
    call Initialise_solid_bodies(0.d0)
    call FindCarrierFluidBlock()
    if (m_nFish /= 1) call parallel_abort('This test requires a single immersed cylinder')
    call distribute_fluid_blocks()
    call allocate_fuild_memory_blocks(1)

    associate (b => LBMblks(VBodies(1)%v_carrierFluidId))
        do trial = 1, 2
            b%den = flow%denIn
            if (trial == 2) then
                do z = 1,b%zDim
                    b%den(z,:,:) = flow%denIn * (1.d0 + 0.08d0*cos(2.d0*pi*(z-1)/b%zDim))
                enddo
            endif
            b%force = 0.d0
            do component = 1,3
                b%uuu(:,:,:,component) = initial(component)
            enddo
            call FSInteraction_force(b%carriedBodies,b%dh,b%dh,b%global_xmin,b%ymin,b%zmin, &
                                     b%xDim,b%yDim,b%zDim,b%global_nx,b%first_x,b%den,b%uuu,b%force)
            metrics = 0.d0
            do component = 1,3
                do x = 1,b%xDim
                    metrics(1) = max(metrics(1),maxval(abs(2.d0*b%den(:,:,x) * &
                        (b%uuu(:,:,x,component)-initial(component))/b%dh - b%force(:,:,x,component))))
                enddo
                fluid_load(component) = sum(b%force(:,:,:,component))*b%dh**3
                body_load(component) = sum(VBodies(1)%rbm%lodFlow(component::6))
            enddo
            metrics(2) = maxval(abs(b%force))
            call max_values(metrics)
            call sum_values(fluid_load)
            if (metrics(2) <= 0.d0 .or. maxval(abs(body_load)) <= 0.d0) call parallel_abort('Missing test load')
            balance_error = maxval(abs(body_load + fluid_load))/maxval(abs(body_load))
            if (is_root) write(*,'(A,I1,2(A,ES12.4))') 'trial ',trial,' half-step error ', &
                metrics(1)/metrics(2),' action-reaction error ',balance_error
            if (.not.(metrics(1)/metrics(2) < 1.d-11 .and. balance_error < 1.d-6)) &
                call parallel_abort('IBM force balance failed')
        enddo
    end associate
    call finish_parallel()
end program
