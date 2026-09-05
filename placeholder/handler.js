exports.handler = async () => ({
  statusCode: 501,
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ message: "Placeholder — deploy auth-lambda CI (update-function-code)" }),
});
