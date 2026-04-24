FROM public.ecr.aws/lambda/python:3.13.2026.03.12.12

# Update + install packages
RUN microdnf update -y && \
    microdnf install -y git && \
    microdnf clean all

# Install dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy function code
COPY lambda_function.py ${LAMBDA_TASK_ROOT}/

CMD ["lambda_function.handler"]
