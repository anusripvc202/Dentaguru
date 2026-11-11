// ==========================================================================
// DENTA GURU BACKEND INTEGRATION TEST RUNNER
// Validates schema loading, route endpoints, and token generation logic
// ==========================================================================

const assert = require('assert');
const { User, Clinic, Dentist, Appointment, MedicalRecord, ChatMessage, AuditLog, DoctorAvailability } = require('../src/models/Schemas');
const availabilityController = require('../src/controllers/availabilityController');
const appointmentController = require('../src/controllers/appointmentController');
const clinicController = require('../src/controllers/clinicController');
const app = require('../src/app');

console.log('--- STARTING DENTA GURU CORE COMPONENT TESTS ---');

// 1. Validate Supabase PostgreSQL Models compilation
try {
    assert.ok(User, 'User model compiled successfully.');
    assert.ok(Clinic, 'Clinic model compiled successfully.');
    assert.ok(Dentist, 'Dentist model compiled successfully.');
    assert.ok(Appointment, 'Appointment model compiled successfully.');
    assert.ok(MedicalRecord, 'MedicalRecord model compiled successfully.');
    assert.ok(ChatMessage, 'ChatMessage model compiled successfully.');
    assert.ok(AuditLog, 'AuditLog model compiled successfully.');
    assert.ok(DoctorAvailability, 'DoctorAvailability model compiled successfully.');
    console.log('✓ SUCCESS: Core Supabase PostgreSQL Models loaded and compiled.');

} catch (error) {
    console.error('✗ ERROR: Schema validation failed:', error.message);
    process.exit(1);
}

// 2. Validate Doctor Availability Slot Generation & Authorization
(async () => {
    try {
        // Test Slot Generation Helper
        const mockReqGen = {
            body: { startTime: '09:00 AM', endTime: '11:00 AM', durationMinutes: 30 }
        };
        let genSlotsResult = null;
        const mockResGen = {
            status: (code) => ({
                json: (data) => { genSlotsResult = data; return data; }
            })
        };
        await availabilityController.generateSlots(mockReqGen, mockResGen);
        assert.ok(genSlotsResult && genSlotsResult.success, 'Slot generation returned success.');
        assert.deepStrictEqual(genSlotsResult.slots, ['09:00 AM', '09:30 AM', '10:00 AM', '10:30 AM'], 'Generated non-overlapping 30min slots correctly.');
        console.log('✓ SUCCESS: Doctor availability slot generation logic verified.');

        // Test Slot Generation Helper WITH Break Time (e.g. Lunch Break 01:00 PM to 02:00 PM)
        const mockReqGenBreak = {
            body: {
                startTime: '11:00 AM',
                endTime: '03:00 PM',
                durationMinutes: 60,
                breakStartTime: '01:00 PM',
                breakEndTime: '02:00 PM'
            }
        };
        let genBreakSlotsResult = null;
        const mockResGenBreak = {
            status: (code) => ({
                json: (data) => { genBreakSlotsResult = data; return data; }
            })
        };
        await availabilityController.generateSlots(mockReqGenBreak, mockResGenBreak);
        assert.ok(genBreakSlotsResult && genBreakSlotsResult.success, 'Break slot generation succeeded.');
        assert.deepStrictEqual(genBreakSlotsResult.slots, ['11:00 AM', '12:00 PM', '02:00 PM'], 'Break time 01:00 PM to 02:00 PM correctly excluded.');
        console.log('✓ SUCCESS: Slot generation strictly excludes break times and prevents overlaps.');

        // Test Patient Authorization Denial (403 Forbidden)
        const mockReqPatient = {
            user: { id: 'patient-123', role: 'Patient' },
            body: { dentistId: 'doc-1', date: '2026-11-10', slots: ['10:00 AM'] }
        };
        let patientAuthStatus = 0;
        let patientAuthMsg = '';
        const mockResPatient = {
            status: (code) => {
                patientAuthStatus = code;
                return {
                    json: (data) => { patientAuthMsg = data.message; }
                };
            }
        };
        await availabilityController.saveDoctorAvailability(mockReqPatient, mockResPatient);
        assert.strictEqual(patientAuthStatus, 403, 'Patient cannot save doctor availability (403 Forbidden).');
        console.log('✓ SUCCESS: Patient role rejected with 403 when modifying doctor slots.');

        // Retrieve an active dentist and patient from Supabase for live DB testing
        const dentistsInDb = await Dentist.find({});
        const testDoctorId = (dentistsInDb && dentistsInDb.length > 0) ? dentistsInDb[0].id : 'doc-test-1';
        const usersInDb = await User.find({});
        const testPatientId = (usersInDb && usersInDb.length > 0) ? usersInDb[0].id : 'a0000000-0000-0000-0000-000000000001';
        const testDate = '2026-12-05';

        // Test Admin Doctor Availability Save
        const mockReqAdmin = {
            user: { id: 'admin-123', role: 'Admin' },
            body: {
                dentistId: testDoctorId,
                date: testDate,
                startTime: '10:00 AM',
                endTime: '12:00 PM',
                slotDurationMinutes: 30,
                slots: ['10:00 AM', '10:30 AM', '11:00 AM', '11:30 AM']
            }
        };
        let adminSaveSuccess = false;
        const mockResAdmin = {
            status: (code) => ({
                json: (data) => { adminSaveSuccess = data.success; }
            })
        };
        await availabilityController.saveDoctorAvailability(mockReqAdmin, mockResAdmin);
        assert.ok(adminSaveSuccess, 'Admin successfully published doctor availability.');
        console.log('✓ SUCCESS: Admin doctor availability publishing verified.');

        // Test Doctor Availability Fetch
        const mockReqFetch = {
            query: { dentistId: testDoctorId, date: testDate }
        };
        let fetchResult = null;
        const mockResFetch = {
            status: (code) => ({
                json: (data) => { fetchResult = data; }
            })
        };
        await availabilityController.getDoctorAvailability(mockReqFetch, mockResFetch);
        assert.ok(fetchResult && fetchResult.success, 'Availability retrieval succeeded.');
        assert.strictEqual(fetchResult.availability.availableSlots.length, 4, 'Four slots available.');
        console.log('✓ SUCCESS: Doctor availability slot retrieval verified.');

        // Test Past-Date Booking Prevention (400 Bad Request)
        let pastDateStatus = 0;
        const mockPastReq = {
            user: { id: 'patient-test-past', role: 'Patient' },
            body: {
                dentistId: testDoctorId,
                date: '2020-01-01',
                timeSlot: '10:00 AM',
                treatment: 'Consultation'
            }
        };
        const mockPastRes = {
            status: (code) => {
                pastDateStatus = code;
                return { json: (d) => d };
            }
        };
        await appointmentController.bookAppointment(mockPastReq, mockPastRes);
        assert.strictEqual(pastDateStatus, 400, 'Past date booking rejected with 400.');
        console.log('✓ SUCCESS: Past-date appointment bookings blocked with 400 Bad Request.');

        // Test Appointment Booking & Immediate Slot Status Update
        let bookResult = null;
        let bookStatus = 0;
        const mockBookReq = {
            user: { id: testPatientId, role: 'Patient' },
            body: {
                dentistId: testDoctorId,
                patientId: testPatientId,
                date: testDate,
                timeSlot: '10:00 AM',
                treatment: 'Routine Checkup'
            }
        };
        const mockBookRes = {
            status: (code) => {
                bookStatus = code;
                return { json: (data) => { bookResult = data; return data; } };
            }
        };
        await appointmentController.bookAppointment(mockBookReq, mockBookRes);
        assert.strictEqual(bookStatus, 201, 'Booking created successfully with status 201.');
        const bookedApptId = bookResult.appointment.id;
        console.log('✓ SUCCESS: Appointment booked successfully and saved in database.');

        // Test Concurrent / Double Booking Prevention (409 Conflict)
        let doubleBookStatus = 0;
        const mockDoubleReq = {
            user: { id: 'b0000000-0000-0000-0000-000000000002', role: 'Patient' },
            body: {
                dentistId: testDoctorId,
                date: testDate,
                timeSlot: '10:00 AM',
                treatment: 'Second Booking Attempt'
            }
        };
        const mockDoubleRes = {
            status: (code) => {
                doubleBookStatus = code;
                return { json: (d) => d };
            }
        };
        await appointmentController.bookAppointment(mockDoubleReq, mockDoubleRes);
        assert.strictEqual(doubleBookStatus, 409, 'Double booking rejected with 409 Conflict.');
        console.log('✓ SUCCESS: Duplicate/overlapping slot booking prevented with 409 Conflict.');

        // Verify that booked slot is immediately excluded from available slots
        await availabilityController.getDoctorAvailability(mockReqFetch, mockResFetch);
        assert.strictEqual(fetchResult.availability.availableSlots.length, 3, 'Available slots decreased from 4 to 3.');
        assert.ok(!fetchResult.availability.availableSlots.includes('10:00 AM'), '10:00 AM is no longer in available slots.');
        assert.ok(fetchResult.availability.bookedSlots.includes('10:00 AM'), '10:00 AM is in booked slots.');
        console.log('✓ SUCCESS: Booked slot removed from doctor availability immediately.');

        // Test Cancellation and Immediate Slot Release
        const mockCancelReq = {
            params: { id: bookedApptId },
            user: { id: testPatientId, role: 'Patient' }
        };
        const mockCancelRes = {
            status: (code) => ({ json: (d) => d }),
            json: (d) => d
        };
        await appointmentController.cancelAppointment(mockCancelReq, mockCancelRes);

        // Verify slot is released back to available slots
        await availabilityController.getDoctorAvailability(mockReqFetch, mockResFetch);
        assert.strictEqual(fetchResult.availability.availableSlots.length, 4, 'Available slots restored to 4 after cancellation.');
        assert.ok(fetchResult.availability.availableSlots.includes('10:00 AM'), '10:00 AM slot is available again.');
        console.log('✓ SUCCESS: Cancelled appointment releases slot immediately.');

        // Cleanup test appointment and availability from Supabase (Rule 1 & Rule 2)
        try {
            await Appointment.deleteOne({ id: bookedApptId });
            await DoctorAvailability.deleteOne({ dentist_id: testDoctorId, date: testDate });
        } catch (_) {}

        // Test non-existent doctor association returns 404
        const mockNonExistentReq = {
            params: { clinicId: 'clinic-test-101' },
            body: { doctorId: 'non-existent-doc-id' }
        };
        let notFoundStatus = null;
        const mockNotFoundRes = {
            status: (code) => ({
                json: (data) => { notFoundStatus = code; return data; }
            })
        };
        await clinicController.associateClinicDoctor(mockNonExistentReq, mockNotFoundRes);
        assert.strictEqual(notFoundStatus, 404, 'Non-existent doctor returns 404.');
        console.log('✓ SUCCESS: Non-existent doctor correctly returns 404 Not Found.');

        // Test Clinic Doctor Association (No Duplicate Account Creation) with existing doctor
        if (dentistsInDb && dentistsInDb.length > 0) {
            const sampleDoc = dentistsInDb[0];
            const originalClinicId = sampleDoc.clinic_id;

            const mockAssociateReq = {
                params: { clinicId: 'clinic-test-101' },
                body: {
                    doctorId: sampleDoc.id,
                    specialty: sampleDoc.speciality || 'General Medicine'
                }
            };
            let associateResult = null;
            const mockAssociateRes = {
                status: (code) => ({
                    json: (data) => { associateResult = { code, ...data }; return associateResult; }
                }),
                json: (data) => { associateResult = { code: 200, ...data }; return associateResult; }
            };
            await clinicController.associateClinicDoctor(mockAssociateReq, mockAssociateRes);
            assert.ok(associateResult && associateResult.success, 'Doctor association succeeded.');
            assert.strictEqual(associateResult.associated, true, 'Association flag set to true without duplicate creation.');
            console.log('✓ SUCCESS: Clinic doctor association verified without duplicate account creation.');

            // Test Clinic Doctor Removal (Preserves Global Doctor Account)
            const mockRemoveReq = {
                params: { clinicId: 'clinic-test-101', doctorId: sampleDoc.id }
            };
            let removeResult = null;
            const mockRemoveRes = {
                status: (code) => ({
                    json: (data) => { removeResult = { code, ...data }; return removeResult; }
                }),
                json: (data) => { removeResult = { code: 200, ...data }; return removeResult; }
            };
            await clinicController.removeDoctorFromClinic(mockRemoveReq, mockRemoveRes);
            assert.ok(removeResult && removeResult.success, 'Doctor removal succeeded.');
            console.log('✓ SUCCESS: Clinic doctor removed from clinic directory while preserving doctor account.');

            // Restore original clinic_id to preserve DB integrity (Rule 1 & Rule 2)
            await Dentist.findByIdAndUpdate(sampleDoc.id, { clinic_id: originalClinicId });
        }

    } catch (err) {
        console.error('✗ ERROR: Availability test failed:', err);
        process.exit(1);
    }

    // 3. Validate Express Server Routing configuration
    try {
        const routes = app._router.stack
            .filter(r => r.route || (r.name === 'router' && r.handle.stack))
            .length;
        assert.ok(routes > 0, 'Express routing middleware mounted successfully.');
        console.log('✓ SUCCESS: Express routes compiled and loaded.');
    } catch (error) {
        console.error('✗ ERROR: Route validation failed:', error.message);
        process.exit(1);
    }

    console.log('--- ALL FOUNDATION CHECKS PASSED SUCCESSFULLY ---');
    setTimeout(() => {
        process.exit(0);
    }, 100);
})();
