const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('crypto');

// Configure AWS SDK from environment variables
// Required env vars: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION, AWS_S3_BUCKET
const s3 = new AWS.S3({
    accessKeyId: process.env.AWS_ACCESS_KEY_ID,
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    region: process.env.AWS_REGION || 'us-east-1',
});

const BUCKET = process.env.AWS_S3_BUCKET || 'dentaguru-secure-storage';

/**
 * Upload a file buffer directly to S3.
 * @param {Buffer} fileBuffer   - File content as buffer
 * @param {string} originalName - Original filename (used to build the S3 key)
 * @param {string} mimeType     - MIME type e.g. 'image/jpeg', 'application/pdf'
 * @param {string} folder       - S3 folder prefix e.g. 'xrays', 'documents', 'avatars'
 * @returns {Promise<{key: string, url: string}>}
 */
const uploadToS3 = async (fileBuffer, originalName, mimeType, folder = 'uploads') => {
    const ext = originalName.split('.').pop();
    const key = `${folder}/${Date.now()}-${Math.random().toString(36).substring(2)}.${ext}`;

    const params = {
        Bucket: BUCKET,
        Key: key,
        Body: fileBuffer,
        ContentType: mimeType,
        ServerSideEncryption: 'AES256', // Server-side encryption at rest
    };

    const result = await s3.upload(params).promise();

    return {
        key: result.Key,
        url: result.Location,
    };
};

/**
 * Generate a time-limited pre-signed URL for secure private file access.
 * Files are NOT public — access is only granted through these signed URLs.
 * @param {string} key        - S3 object key
 * @param {number} expiresIn  - URL expiry in seconds (default: 15 minutes)
 * @returns {Promise<string>} - Pre-signed URL
 */
const getSignedUrl = async (key, expiresIn = 900) => {
    const params = {
        Bucket: BUCKET,
        Key: key,
        Expires: expiresIn,
    };

    return s3.getSignedUrlPromise('getObject', params);
};

/**
 * Delete a file from S3.
 * @param {string} key - S3 object key to delete
 */
const deleteFromS3 = async (key) => {
    const params = { Bucket: BUCKET, Key: key };
    await s3.deleteObject(params).promise();
    console.log(`✅ S3 file deleted: ${key}`);
};

module.exports = { uploadToS3, getSignedUrl, deleteFromS3, s3, BUCKET };
