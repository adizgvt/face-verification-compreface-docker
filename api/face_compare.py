from flask import Flask, request, jsonify
import requests
import base64
import io
import tempfile
import subprocess
import os
import uuid

app = Flask(__name__)

# Replace with your actual Compreface credentials and endpoint
COMPRE_FACE_URL = os.getenv('COMPRE_FACE_URL', 'http://localhost:8000/api/v1/verification/verify')
COMPRE_FACE_API_KEY = os.getenv('COMPRE_FACE_API_KEY', '95b5a075-85fb-4027-ba71-c577687b2a23')

# Default parameters, can be adjusted or made dynamic as needed
DEFAULT_LIMIT = 1
DEFAULT_PREDICTION_COUNT = 1
DEFAULT_DET_PROB_THRESHOLD = 0.8
DEFAULT_FACE_PLUGINS = ""
DEFAULT_STATUS = ""

def auto_orient_and_strip_jpeg_to_file(image_b64, unique_name_prefix):
    """
    Decodes base64, orients and strips exif, writes result to a unique JPEG temp file, and returns the temp file path.
    The file must be manually deleted by the caller.
    """
    try:
        image_bytes = base64.b64decode(image_b64)
        with tempfile.NamedTemporaryFile(delete=False, suffix=f"_{unique_name_prefix}_src.jpg") as source:
            source.write(image_bytes)
            source.flush()
            source_name = source.name

        with tempfile.NamedTemporaryFile(delete=False, suffix=f"_{unique_name_prefix}_fixed.jpg") as fixed:
            fixed_name = fixed.name

        subprocess.run(
            ['convert', source_name, '-auto-orient', '-strip', fixed_name],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        os.remove(source_name)  # Remove source temp as soon as not needed
        return fixed_name
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"ImageMagick conversion failed: {e.stderr.decode()}")
    except Exception as e:
        # Attempt clean up
        for fn in (locals().get('source_name'), locals().get('fixed_name')):
            if fn and os.path.exists(fn):
                try:
                    os.remove(fn)
                except Exception:
                    pass
        raise RuntimeError(f"Image normalization failed: {e}")

@app.route('/')
def index():
    return jsonify({"message": "Welcome to the Compreface Face Comparison API"})

@app.route('/compare-faces', methods=['POST'])
def compare_faces():
    """
    Receives two images as base64 encoded strings in JSON input,
    auto-orients and strips exif via ImageMagick, saves as unique files,
    sends them to the Compreface verification endpoint using multipart/form-data
    with the appropriate query parameters, and returns the verification results.
    All temp files are securely deleted after use.
    """
    # Ensure the received data is JSON
    if not request.is_json:
        return jsonify({"error": "Content-Type must be application/json"}), 400

    data = request.get_json()
    image1 = data.get('image1')
    image2 = data.get('image2')

    if not image1 or not image2:
        return jsonify({"error": "Both image1 and image2 fields are required in JSON"}), 400

    # Optional: accept overriding params from JSON
    limit = data.get('limit', DEFAULT_LIMIT)
    prediction_count = data.get('prediction_count', DEFAULT_PREDICTION_COUNT)
    det_prob_threshold = data.get('det_prob_threshold', DEFAULT_DET_PROB_THRESHOLD)
    face_plugins = data.get('face_plugins', DEFAULT_FACE_PLUGINS)
    status = data.get('status', DEFAULT_STATUS)

    unique_id = uuid.uuid4().hex
    source_image_path = None
    target_image_path = None

    try:
        # Each output image will have a unique name containing the UUID
        source_image_path = auto_orient_and_strip_jpeg_to_file(image1, f"source_{unique_id}")
        target_image_path = auto_orient_and_strip_jpeg_to_file(image2, f"target_{unique_id}")

        files = {
            'source_image': (os.path.basename(source_image_path), open(source_image_path, 'rb'), 'image/jpeg'),
            'target_image': (os.path.basename(target_image_path), open(target_image_path, 'rb'), 'image/jpeg')
        }

        headers = {
            "x-api-key": COMPRE_FACE_API_KEY
            # Do not set Content-Type, requests will set it for multipart automatically
        }

        params = {
            "limit": limit,
            "prediction_count": prediction_count,
            "det_prob_threshold": det_prob_threshold,
            "face_plugins": face_plugins,
            "status": status
        }

        try:
            resp = requests.post(COMPRE_FACE_URL, headers=headers, files=files, params=params)
            if resp.status_code != 200:
                return jsonify({"error": "Compreface verification failed", "details": resp.text}), 500

            compreface_result = resp.json()
            try:
                result = compreface_result.get('result')[0]
                face_matches = result.get('face_matches', [])
                similarity = None
                distance = None
                is_match = False

                if face_matches:
                    matched_face = face_matches[0]
                    similarity = matched_face.get('similarity')
                    if similarity is not None:
                        similarity = float(similarity)
                        distance = 1.0 - similarity
                        threshold = 0.8
                        is_match = similarity >= threshold

                response = {
                    "similarity": round(similarity * 100, 2),
                    "distance": round(distance * 100, 2),
                    "match": is_match
                }
                return jsonify(response)
            except Exception:
                return jsonify({"error": "Unexpected Compreface response structure", "details": str(compreface_result)}), 500
        finally:
            # Always close and delete temp image files
            for file_entry in files.values():
                try:
                    file_entry[1].close()
                except Exception:
                    pass
            for temp_path in (source_image_path, target_image_path):
                if temp_path and os.path.exists(temp_path):
                    try:
                        os.remove(temp_path)
                    except Exception:
                        pass
    except Exception as e:
        # Clean up temp files if they've been created.
        for temp_path in (source_image_path, target_image_path):
            if temp_path and os.path.exists(temp_path):
                try:
                    os.remove(temp_path)
                except Exception:
                    pass
        return jsonify({"error": "Error decoding or processing images", "details": str(e)}), 400

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')
