const multer = require('multer');
const { uploadToS3, getSignedUrl } = require('../services/storageService');

// Use memory storage — we stream the buffer directly to S3
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 20 * 1024 * 1024 }, // 20 MB max per file
    fileFilter: (req, file, cb) => {
        const allowed = [
            'image/jpeg', 'image/png', 'image/webp',
            'application/pdf',
            'application/dicom', 'image/dicom' // DICOM X-ray support
        ];
        if (allowed.includes(file.mimetype)) {
            cb(null, true);
        } else {
            cb(new Error(`Unsupported file type: ${file.mimetype}`), false);
        }
    },
});

/**
 * POST /api/v1/upload
 * Upload a single file (X-ray, document, avatar) to AWS S3.
 * Requires: multipart/form-data with field "file" and optional field "folder"
 * Auth: JWT required
 */
exports.uploadFile = [
    upload.single('file'),
    async (req, res) => {
        try {
            if (!req.file) {
                return res.status(400).json({ success: false, message: 'No file provided.' });
            }

            const folder = req.body.folder || 'uploads';
            const allowedFolders = ['xrays', 'documents', 'avatars', 'uploads'];
            if (!allowedFolders.includes(folder)) {
                return res.status(400).json({ success: false, message: `Invalid folder. Allowed: ${allowedFolders.join(', ')}` });
            }

            const { key, url } = await uploadToS3(
                req.file.buffer,
                req.file.originalname,
                req.file.mimetype,
                folder
            );

            res.status(201).json({
                success: true,
                message: 'File uploaded securely to cloud storage.',
                key,    // Store this key in your DB (MedicalRecord.xrayUrls, etc.)
                url,    // Direct S3 URL (not recommended to share publicly)
            });
        } catch (err) {
            console.error('Upload Error:', err.message);
            res.status(500).json({ success: false, message: err.message || 'Upload failed.' });
        }
    },
];

/**
 * GET /api/v1/upload/signed-url?key=<s3-key>
 * Generate a 15-minute pre-signed URL for secure private file access.
 * Auth: JWT required
 */
exports.getSignedFileUrl = async (req, res) => {
    const { key } = req.query;
    if (!key) {
        return res.status(400).json({ success: false, message: 'File key is required.' });
    }

    try {
        const signedUrl = await getSignedUrl(key, 900); // 15 minutes
        res.json({
            success: true,
            signedUrl,
            expiresIn: '15 minutes',
        });
    } catch (err) {
        console.error('Signed URL Error:', err.message);
        res.status(500).json({ success: false, message: 'Failed to generate secure access URL.' });
    }
};
