import os
import json
from fastapi import FastAPI, File, UploadFile, Header, HTTPException
from fastapi.responses import JSONResponse
from docling.document_converter import DocumentConverter
from docling.pipeline.standard_pdf_pipeline import StandardPdfPipeline
from docling.pipeline.standard_ocr_pipeline import StandardOcrPipeline

app = FastAPI(title="Spread Docling Extraction Service", version="1.0.0")

DOCLING_API_KEY = os.getenv("DOCLING_API_KEY", "dev-key-change-in-production")
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB
ALLOWED_TYPES = {"application/pdf", "image/jpeg", "image/png"}

converter = DocumentConverter()

@app.post("/extract")
async def extract(
    file: UploadFile = File(...),
    api_key: str = Header(None, alias="Api-Key")
):
    """
    Extract tables and text from a financial document.

    Request:
    - file: PDF, JPEG, or PNG
    - Api-Key header: authentication key

    Response:
    {
        "tables": "markdown-formatted tables",
        "page_count": N,
        "job_id": "unique extraction id"
    }
    """

    # Validate API key
    if api_key != DOCLING_API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")

    # Validate content type
    if file.content_type not in ALLOWED_TYPES:
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported file type: {file.content_type}. Supported: PDF, JPEG, PNG"
        )

    # Read file
    try:
        content = await file.read()
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to read file: {str(e)}")

    # Validate file size
    if len(content) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=413,
            detail=f"File too large: {len(content)} bytes (max {MAX_FILE_SIZE})"
        )

    # Extract
    try:
        # Convert file to bytes
        doc_result = converter.convert_bytes(
            content,
            file_type=_infer_document_type(file.content_type)
        )

        # Extract tables in markdown format
        markdown_tables = _extract_tables_as_markdown(doc_result)
        page_count = len(doc_result.pages) if hasattr(doc_result, 'pages') else 1
        job_id = _generate_job_id(file.filename)

        return JSONResponse(
            status_code=200,
            content={
                "tables": markdown_tables,
                "page_count": page_count,
                "job_id": job_id
            }
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Extraction failed: {str(e)}"
        )

def _infer_document_type(content_type):
    """Map content type to Docling document type."""
    if content_type == "application/pdf":
        return "pdf"
    elif content_type in ("image/jpeg", "image/png"):
        return "image"
    return "pdf"  # Default

def _extract_tables_as_markdown(doc_result):
    """
    Extract tables from Docling document and format as markdown.
    Returns markdown string with all tables found in the document.
    """
    markdown_output = []

    for page_num, page in enumerate(doc_result.pages, 1):
        for element in page.elements:
            # Check if element is a table
            if hasattr(element, 'data_cells') or element.__class__.__name__ == 'TableElement':
                markdown_table = _table_to_markdown(element, page_num)
                if markdown_table:
                    markdown_output.append(markdown_table)

    return "\n\n".join(markdown_output) if markdown_output else "No tables found"

def _table_to_markdown(table_element, page_num):
    """Convert a Docling table element to markdown format."""
    try:
        # Docling table structure: get rows and cells
        if not hasattr(table_element, 'rows') or not table_element.rows:
            return None

        markdown_lines = [f"**Table from page {page_num}:**\n"]

        for row in table_element.rows:
            cells = [str(cell.text) if hasattr(cell, 'text') else str(cell) for cell in row.cells]
            markdown_lines.append("| " + " | ".join(cells) + " |")

            # Add header separator after first row
            if row == table_element.rows[0]:
                markdown_lines.append("|" + "|".join(["---" for _ in cells]) + "|")

        return "\n".join(markdown_lines)
    except Exception as e:
        # Fallback: return raw table representation
        return f"Table from page {page_num}: {str(table_element)}\n"

def _generate_job_id(filename):
    """Generate a unique job ID from filename and timestamp."""
    import hashlib
    import time
    timestamp = str(int(time.time() * 1000))
    file_hash = hashlib.md5(filename.encode()).hexdigest()[:8]
    return f"job_{file_hash}_{timestamp}"

@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "healthy"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
