import os
import subprocess
import boto3

s3 = boto3.client('s3', endpoint_url=os.environ.get('AWS_ENDPOINT_URL'))

def handler(event, context):
    # 1. Get data event
    bucket_in = event['bucket_in']
    key_in = event['key_in']
    bucket_out = os.environ['BUCKET_OUT']
    resolution = os.environ['RESOLUTION']

    download_path = f"/tmp/{key_in}"
    output_path = f"/tmp/processed_{key_in}"

    # 2. Download the video from S3
    s3.download_file(bucket_in, key_in, download_path)

    # 3. Process the video using ffmpeg
    command = [
        './ffmpeg', '-i', download_path,
        '-vf', f'scale={resolution}',
        '-c:v', 'libx264', '-crf', '28', '-preset', 'veryfast',
        '-y', output_path
    ]
    subprocess.run(command, check=True)

    # 4. Upload the processed video back to S3
    s3.upload_file(output_path, bucket_out, key_in)

    return {
        'status': 'success',
        'resolution': resolution,
        'bucket': bucket_out,
        'key': key_in
    }