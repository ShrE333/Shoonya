const fs = require('fs');
const path = require('path');
const https = require('https');

const MODELS_DIR = path.join(__dirname, '../public/models');
const BASE_URL = 'https://raw.githubusercontent.com/justadudewhohacks/face-api.js/master/weights/';

const FILES = [
  'tiny_face_detector_model-shard1',
  'tiny_face_detector_model-weights_manifest.json',
  'face_landmark_68_model-shard1',
  'face_landmark_68_model-weights_manifest.json',
  'age_gender_model-shard1',
  'age_gender_model-weights_manifest.json'
];

if (!fs.existsSync(MODELS_DIR)){
    fs.mkdirSync(MODELS_DIR, { recursive: true });
}

FILES.forEach(file => {
  const destPath = path.join(MODELS_DIR, file);
  if (!fs.existsSync(destPath)) {
    console.log(`Downloading ${file}...`);
    const fileStream = fs.createWriteStream(destPath);
    https.get(`${BASE_URL}${file}`, response => {
      response.pipe(fileStream);
      fileStream.on('finish', () => {
        fileStream.close();
        console.log(`Finished ${file}`);
      });
    }).on('error', err => {
      fs.unlink(destPath, () => {});
      console.error(`Error downloading ${file}: ${err.message}`);
    });
  } else {
    console.log(`${file} already exists, skipping.`);
  }
});
