const test = require('node:test');
const assert = require('node:assert/strict');
const Schemas = require('../src/models/Schemas');
const clinicController = require('../src/controllers/clinicController');
const appointmentController = require('../src/controllers/appointmentController');

function createMockRes() {
    const res = {
        statusCode: 200,
        body: null,
        status(code) {
            this.statusCode = code;
            return this;
        },
        json(payload) {
            this.body = payload;
            return this;
        },
    };
    return res;
}

test('resolveDoctorConsultationModes: unknown doctor defaults to onlineConsultationEnabled=false, inPersonConsultationEnabled=true', () => {
    const unknownDoc = {
        id: 'doc-unknown-1',
        name: 'Dr. Legacy Unconfigured',
        speciality: 'General Medicine',
        availability_status: 'Available',
    };
    const modes = Schemas.resolveDoctorConsultationModes(unknownDoc);
    assert.equal(modes.onlineConsultationEnabled, false);
    assert.equal(modes.inPersonConsultationEnabled, true);
    assert.equal(modes.hasExplicitConfiguration, false);
    assert.deepEqual(modes.consultationModes, ['In-Person']);
});

test('getAllDentists filters strictly by Online vs Offline consultation modes and excludes unknown doctors from Online', async (t) => {
    const mockDentists = [
        {
            id: '11111111-1111-4111-8111-111111111101',
            user_id: '21111111-1111-4111-8111-111111111101',
            name: 'Dr. Online Only Specialist',
            speciality: 'Dermatology',
            qualifications: 'MBBS, MD',
            experience_years: 8,
            clinic_name: 'TeleDerma Hub',
            city: 'Hyderabad',
            state: 'Telangana',
            pincode: '500081',
            availability_status: 'Available',
            online_consultation_enabled: true,
            in_person_consultation_enabled: false,
            users: { id: '21111111-1111-4111-8111-111111111101', name: 'Dr. Online Only Specialist' },
        },
        {
            id: '11111111-1111-4111-8111-111111111102',
            user_id: '21111111-1111-4111-8111-111111111102',
            name: 'Dr. Offline Clinic Only',
            speciality: 'Orthopedics',
            qualifications: 'MBBS, MS',
            experience_years: 12,
            clinic_name: 'OrthoCare Clinic',
            clinic_address: 'Road No 12, Banjara Hills',
            city: 'Hyderabad',
            state: 'Telangana',
            pincode: '500034',
            latitude: 17.4156,
            longitude: 78.4347,
            availability_status: 'Available',
            online_consultation_enabled: false,
            in_person_consultation_enabled: true,
            users: { id: '21111111-1111-4111-8111-111111111102', name: 'Dr. Offline Clinic Only' },
        },
        {
            id: '11111111-1111-4111-8111-111111111103',
            user_id: '21111111-1111-4111-8111-111111111103',
            name: 'Dr. Hybrid Both Modes',
            speciality: 'Cardiology',
            qualifications: 'MBBS, MD, DM',
            experience_years: 15,
            clinic_name: 'HeartCare Center',
            clinic_address: 'Jubilee Hills Checkpost',
            city: 'Hyderabad',
            state: 'Telangana',
            pincode: '500033',
            availability_status: 'Available',
            online_consultation_enabled: true,
            in_person_consultation_enabled: true,
            users: { id: '21111111-1111-4111-8111-111111111103', name: 'Dr. Hybrid Both Modes' },
        },
        {
            id: '11111111-1111-4111-8111-111111111104',
            user_id: '21111111-1111-4111-8111-111111111104',
            name: 'Dr. Unknown Legacy Doctor',
            speciality: 'General Medicine',
            qualifications: 'MBBS',
            experience_years: 6,
            clinic_name: 'City General Clinic',
            city: 'Hyderabad',
            state: 'Telangana',
            pincode: '500001',
            availability_status: 'Available',
            users: { id: '21111111-1111-4111-8111-111111111104', name: 'Dr. Unknown Legacy Doctor' },
        },
    ];

    const origDentistFind = Schemas.Dentist.find;
    const origUserFind = Schemas.User.find;
    Schemas.Dentist.find = async () => mockDentists.map((d) => ({ ...d }));
    Schemas.User.find = async () => [];
    t.after(() => {
        Schemas.Dentist.find = origDentistFind;
        Schemas.User.find = origUserFind;
    });

    // 1. Online Consultation Filter -> Only Dr. Online Only & Dr. Hybrid Both Modes
    const resOnline = createMockRes();
    await clinicController.getAllDentists(
        { query: { consultationMode: 'Online' }, user: { role: 'patient' } },
        resOnline
    );
    assert.equal(resOnline.statusCode, 200);
    const onlineNames = resOnline.body.doctors.map((d) => d.name);
    assert.deepEqual(onlineNames, ['Dr. Online Only Specialist', 'Dr. Hybrid Both Modes']);
    assert.equal( onlineNames.includes('Dr. Offline Clinic Only'), false);
    assert.equal(onlineNames.includes('Dr. Unknown Legacy Doctor'), false);

    // 2. Offline Consultation Filter -> Dr. Offline Clinic Only, Dr. Hybrid Both Modes, and Dr. Unknown Legacy Doctor (excludes Online-Only!)
    const resOffline = createMockRes();
    await clinicController.getAllDentists(
        { query: { consultationMode: 'Offline' }, user: { role: 'patient' } },
        resOffline
    );
    assert.equal(resOffline.statusCode, 200);
    const offlineNames = resOffline.body.doctors.map((d) => d.name);
    assert.equal(offlineNames.includes('Dr. Offline Clinic Only'), true);
    assert.equal(offlineNames.includes('Dr. Hybrid Both Modes'), true);
    assert.equal(offlineNames.includes('Dr. Online Only Specialist'), false);
});

test('updateDoctorProfile rejects disabling both Online and In-Person consultation modes', async (t) => {
    const origFindById = Schemas.Dentist.findById;
    Schemas.Dentist.findById = async () => ({
        id: '11111111-1111-4111-8111-111111111102',
        user_id: '21111111-1111-4111-8111-111111111102',
        online_consultation_enabled: false,
        in_person_consultation_enabled: true,
    });
    t.after(() => {
        Schemas.Dentist.findById = origFindById;
    });

    const req = {
        params: { id: '11111111-1111-4111-8111-111111111102' },
        user: { id: '21111111-1111-4111-8111-111111111102', role: 'doctor' },
        body: {
            onlineConsultationEnabled: false,
            inPersonConsultationEnabled: false,
        },
    };
    const res = createMockRes();
    await clinicController.updateDoctorProfile(req, res);
    assert.equal(res.statusCode, 400);
    assert.equal(res.body.code, 'INVALID_CONSULTATION_MODES');
});

test('bookAppointment blocks booking Online with offline-only doctor and blocks booking In-Person with online-only doctor', async (t) => {
    const tomorrow = new Date(Date.now() + 2 * 24 * 60 * 60 * 1000);
    const ymd = `${tomorrow.getFullYear()}-${String(tomorrow.getMonth() + 1).padStart(2, '0')}-${String(tomorrow.getDate()).padStart(2, '0')}`;

    const origFindById = Schemas.Dentist.findById;
    const origAvailFindOne = Schemas.DoctorAvailability.findOne;
    const origGetSchedule = Schemas.DoctorAvailability.getSchedule;
    const origGetBlockedSlots = Schemas.DoctorAvailability.getBlockedSlotsForDate;
    const origApptFind = Schemas.Appointment.find;

    const doctorsById = {
        'doc-offline-only': {
            id: 'doc-offline-only',
            user_id: 'u-offline-only',
            name: 'Dr. Offline Clinic Only',
            availability_status: 'Available',
            online_consultation_enabled: false,
            in_person_consultation_enabled: true,
        },
        'doc-online-only': {
            id: 'doc-online-only',
            user_id: 'u-online-only',
            name: 'Dr. Online Video Only',
            availability_status: 'Available',
            online_consultation_enabled: true,
            in_person_consultation_enabled: false,
        },
    };

    Schemas.Dentist.findById = async (id) => doctorsById[id] || null;
    Schemas.DoctorAvailability.findOne = async () => null;
    Schemas.DoctorAvailability.getSchedule = async () => ({
        workingDays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
        startTime: '09:00 AM',
        endTime: '05:00 PM',
        slotDurationMinutes: 30,
        onlineEnabled: true,
        inPersonEnabled: true,
        isConfigured: true,
    });
    Schemas.DoctorAvailability.getBlockedSlotsForDate = async () => [];
    Schemas.Appointment.find = async () => [];

    t.after(() => {
        Schemas.Dentist.findById = origFindById;
        Schemas.DoctorAvailability.findOne = origAvailFindOne;
        Schemas.DoctorAvailability.getSchedule = origGetSchedule;
        Schemas.DoctorAvailability.getBlockedSlotsForDate = origGetBlockedSlots;
        Schemas.Appointment.find = origApptFind;
    });

    // 1. Attempt to book Online consultation with an offline-only doctor -> Rejected (400)
    const resOnlineWithOfflineDoc = createMockRes();
    await appointmentController.bookAppointment(
        {
            user: { id: 'pat-1', role: 'patient' },
            body: {
                dentistId: 'doc-offline-only',
                patientId: 'pat-1',
                date: ymd,
                timeSlot: '10:00 AM',
                treatment: 'General Consultation',
                consultationMode: 'Online',
            },
        },
        resOnlineWithOfflineDoc
    );
    assert.equal(resOnlineWithOfflineDoc.statusCode, 400);
    assert.equal(resOnlineWithOfflineDoc.body.reason, 'CONSULTATION_MODE_NOT_SUPPORTED');

    // 2. Attempt to book In-Person consultation with an online-only doctor -> Rejected (400)
    const resInPersonWithOnlineDoc = createMockRes();
    await appointmentController.bookAppointment(
        {
            user: { id: 'pat-1', role: 'patient' },
            body: {
                dentistId: 'doc-online-only',
                patientId: 'pat-1',
                date: ymd,
                timeSlot: '10:00 AM',
                treatment: 'General Consultation',
                consultationMode: 'In-Person',
            },
        },
        resInPersonWithOnlineDoc
    );
    assert.equal(resInPersonWithOnlineDoc.statusCode, 400);
    assert.equal(resInPersonWithOnlineDoc.body.reason, 'CONSULTATION_MODE_NOT_SUPPORTED');
});
