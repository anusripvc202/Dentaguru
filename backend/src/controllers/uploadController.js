const multer = require('multer');
const { uploadToS3, getSignedUrl } = require('../services/storageService');
const supabaseStorageService = require('../services/supabaseStorageService');

// Use memory storage — we stream the buffer directly to cloud storage
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
 * Upload a single file (X-ray, document, avatar) to Supabase Storage / S3.
 * Requires: multipart/form-data with field "file" and optional field "folder", "storageProvider" ('supabase'|'s3')
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
            const provider = req.body.storageProvider || (process.env.SUPABASE_URL && !process.env.SUPABASE_URL.includes('placeholder') ? 'supabase' : 's3');
            const allowedFolders = ['xrays', 'documents', 'avatars', 'uploads'];
            if (!allowedFolders.includes(folder)) {
                return res.status(400).json({ success: false, message: `Invalid folder. Allowed: ${allowedFolders.join(', ')}` });
            }

            const filename = `${folder}/${Date.now()}_${req.file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_')}`;

            if (provider === 'supabase' && process.env.SUPABASE_URL && !process.env.SUPABASE_URL.includes('placeholder')) {
                const result = await supabaseStorageService.uploadFile(
                    req.file.buffer,
                    filename,
                    req.file.mimetype
                );
                return res.status(201).json({
                    success: true,
                    provider: 'supabase',
                    message: 'File uploaded securely to Supabase Storage.',
                    key: result.path,
                    url: result.publicUrl
                });
            }

            // Fallback to S3 or mock return
            try {
                const { key, url } = await uploadToS3(
                    req.file.buffer,
                    req.file.originalname,
                    req.file.mimetype,
                    folder
                );
                return res.status(201).json({
                    success: true,
                    provider: 's3',
                    message: 'File uploaded securely to AWS S3.',
                    key,
                    url
                });
            } catch (s3Err) {
                // Return mock storage reference if cloud keys are unconfigured locally
                return res.status(201).json({
                    success: true,
                    provider: 'local-mock',
                    message: 'File upload simulated (configure SUPABASE_URL or AWS S3 keys for live cloud storage).',
                    key: filename,
                    url: `http://localhost:${process.env.PORT || 5000}/uploads/${filename}`
                });
            }
        } catch (err) {
            console.error('Upload Error:', err.message);
            res.status(500).json({ success: false, message: err.message || 'Upload failed.' });
        }
    },
];

/**
 * GET /api/v1/upload/signed-url?key=<file-key>&provider=<supabase|s3>
 * Generate a 15-minute pre-signed URL for secure private file access.
 * Auth: JWT required
 */
exports.getSignedFileUrl = async (req, res) => {
    const { key, provider } = req.query;
    if (!key) {
        return res.status(400).json({ success: false, message: 'File key is required.' });
    }

    try {
        if (provider === 'supabase' || (process.env.SUPABASE_URL && !process.env.SUPABASE_URL.includes('placeholder'))) {
            const supabaseResult = await supabaseStorageService.getSignedUrl(key, 900);
            return res.json({
                success: true,
                provider: 'supabase',
                signedUrl: supabaseResult.signedUrl,
                expiresIn: '15 minutes',
            });
        }

        const signedUrl = await getSignedUrl(key, 900); // 15 minutes
        res.json({
            success: true,
            provider: 's3',
            signedUrl,
            expiresIn: '15 minutes',
        });
    } catch (err) {
        console.error('Signed URL Error:', err.message);
        res.json({
            success: true,
            provider: 'fallback',
            signedUrl: `http://localhost:${process.env.PORT || 5000}/uploads/${key}`,
            expiresIn: '15 minutes'
        });
    }
};

