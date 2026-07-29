const mongoose = require('mongoose');
const bcrypt = require('bcryptjs');

// 1. USER SCHEMA (Auth & Core User Identity)
const UserSchema = new mongoose.Schema({
    name: { type: String, required: true },
    email: { type: String, required: true, unique: true, index: true },
    password: { type: String, required: true },
    phone: { type: String, required: true, unique: true, index: true },
    role: { 
        type: String, 
        enum: ['Patient', 'Dentist', 'Clinic', 'SuperAdmin'], 
        default: 'Patient' 
    },
    biometricToken: { type: String, default: null },
    deviceToken: { type: String, default: null }, // FCM Push Notification Token
    refreshTokens: [{ type: String }],
    walletBalance: { type: Number, default: 0 },
    loyaltyPoints: { type: Number, default: 0 }
}, { timestamps: true });

// Pre-save password hashing
UserSchema.pre('save', async function(next) {
    if (!this.isModified('password')) return next();
    try {
        const salt = await bcrypt.genSalt(10);
        this.password = await bcrypt.hash(this.password, salt);
        next();
    } catch (err) {
        next(err);
    }
});

// Compare password helper
UserSchema.methods.comparePassword = async function(candidatePassword) {
    return await bcrypt.compare(candidatePassword, this.password);
};

// 2. CLINIC PROFILE SCHEMA
const ClinicSchema = new mongoose.Schema({
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    clinicName: { type: String, required: true },
    location: { type: String, required: true },
    coordinates: {
        type: { type: String, default: 'Point' },
        coordinates: { type: [Number], index: '2dsphere' } // [Longitude, Latitude]
    },
    verified: { type: Boolean, default: false },
    plan: { type: String, enum: ['Standard', 'Premium'], default: 'Standard' },
    activeSlots: [{ type: String }], // Array of timing slot strings e.g. ["09:00 AM", "10:00 AM"]
    services: [{ type: String }],
    pricing: [{ service: String, price: Number }],
    rating: { type: Number, default: 0 },
    reviewsCount: { type: Number, default: 0 }
}, { timestamps: true });

// 3. DENTIST PROFILE SCHEMA
const DentistSchema = new mongoose.Schema({
    userId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    clinicId: { type: mongoose.Schema.Types.ObjectId, ref: 'Clinic', required: true, index: true },
    speciality: { type: String, required: true },
    licenseNumber: { type: String, required: true, unique: true },
    availabilityStatus: { type: String, enum: ['Available', 'On Break', 'Offline'], default: 'Available' },
    rating: { type: Number, default: 0 },
    reviewsCount: { type: Number, default: 0 }
}, { timestamps: true });

// 4. APPOINTMENT SCHEMA
const AppointmentSchema = new mongoose.Schema({
    patientId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    dentistId: { type: mongoose.Schema.Types.ObjectId, ref: 'Dentist', required: true, index: true },
    clinicId: { type: mongoose.Schema.Types.ObjectId, ref: 'Clinic', required: true, index: true },
    date: { type: Date, required: true, index: true },
    timeSlot: { type: String, required: true }, // e.g. "09:30 AM"
    treatment: { type: String, required: true },
    status: { 
        type: String, 
        enum: ['pending', 'confirmed', 'rescheduled', 'cancelled'], 
        default: 'pending' 
    },
    paymentStatus: { type: String, enum: ['unpaid', 'paid', 'refunded'], default: 'unpaid' },
    paymentId: { type: String, default: null },
    qrCodeString: { type: String }
}, { timestamps: true });

// 5. MEDICAL RECORD SCHEMA
const MedicalRecordSchema = new mongoose.Schema({
    patientId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, index: true },
    dentistId: { type: mongoose.Schema.Types.ObjectId, ref: 'Dentist', required: true },
    diagnosis: { type: String, required: true },
    notes: { type: String },
    prescriptions: [{ medicine: String, dosage: String, frequency: String }],
    xrayUrls: [{ type: String }], // URLs to secure cloud files
    labReportUrls: [{ type: String }]
}, { timestamps: true });

// 6. CHAT MESSAGE SCHEMA
const ChatMessageSchema = new mongoose.Schema({
    roomId: { type: String, required: true, index: true },
    senderId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    receiverId: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    message: { type: String, required: true },
    type: { type: String, enum: ['text', 'image', 'file'], default: 'text' },
    read: { type: Boolean, default: false }
}, { timestamps: true });

// Compile models
const User = mongoose.model('User', UserSchema);
const Clinic = mongoose.model('Clinic', ClinicSchema);
const Dentist = mongoose.model('Dentist', DentistSchema);
const Appointment = mongoose.model('Appointment', AppointmentSchema);
const MedicalRecord = mongoose.model('MedicalRecord', MedicalRecordSchema);
const ChatMessage = mongoose.model('ChatMessage', ChatMessageSchema);

module.exports = {
    User,
    Clinic,
    Dentist,
    Appointment,
    MedicalRecord,
    ChatMessage
};
