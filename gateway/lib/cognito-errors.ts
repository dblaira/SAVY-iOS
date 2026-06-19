export function cognitoErrorName(error: unknown): string | null {
  if (!error || typeof error !== "object") return null;
  if ("name" in error && typeof (error as { name: unknown }).name === "string") {
    return (error as { name: string }).name;
  }
  return null;
}

export function cognitoErrorMessage(error: unknown): string {
  if (error instanceof Error) return error.message;
  return String(error);
}

export function isNotConfirmedError(error: unknown): boolean {
  const name = cognitoErrorName(error);
  const message = cognitoErrorMessage(error);
  return (
    name === "UserNotConfirmedException" ||
    /not confirmed/i.test(message)
  );
}

export function isUserNotFoundError(error: unknown): boolean {
  const name = cognitoErrorName(error);
  return name === "UserNotFoundException";
}

export function isUsernameExistsError(error: unknown): boolean {
  const name = cognitoErrorName(error);
  const message = cognitoErrorMessage(error);
  return (
    name === "UsernameExistsException" ||
    /already exists/i.test(message)
  );
}
