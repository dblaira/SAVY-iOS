import { PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { randomUUID } from "node:crypto";

function s3Client(): S3Client | null {
  const region = process.env.AWS_REGION ?? process.env.COGNITO_REGION ?? "us-west-2";
  if (!process.env.AWS_ACCESS_KEY_ID || !process.env.AWS_SECRET_ACCESS_KEY) {
    return null;
  }
  return new S3Client({ region });
}

export function reminderImageBucket(): string | null {
  const bucket = process.env.SAVY_CAPTURES_BUCKET?.trim();
  return bucket || null;
}

export async function uploadReminderImage(
  userId: string,
  reminderId: string,
  bytes: Buffer,
  contentType = "image/jpeg"
): Promise<string> {
  const bucket = reminderImageBucket();
  const client = s3Client();
  if (!bucket || !client) {
    throw new Error("SAVY_CAPTURES_BUCKET and AWS credentials are required for image upload");
  }

  const key = `reminders/${userId}/${reminderId}/${randomUUID()}.jpg`;
  await client.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: bytes,
      ContentType: contentType,
    })
  );

  return `s3://${bucket}/${key}`;
}
