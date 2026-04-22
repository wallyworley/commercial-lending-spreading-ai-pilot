import os
import tempfile
import logging
import time
from io import BytesIO
from pathlib import Path
from fastapi import FastAPI, File, UploadFile, Header, HTTPException
from fastapi.responses import JSONResponse

app = FastAPI(title="Spread Docling Extraction Service", version="1.0.0")
logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"))
logger = logging.getLogger("spread-docling")

DOCLING_API_KEY = os.getenv("DOCLING_API_KEY", "dev-key-change-in-production")
MAX_FILE_SIZE = 50 * 1024 * 1024  # 50MB
ALLOWED_TYPES = {"application/pdf", "image/jpeg", "image/png"}
DOCLING_ENABLE_OCR = os.getenv("DOCLING_ENABLE_OCR", "false").lower() == "true"
DOCLING_TABLE_STRUCTURE = os.getenv("DOCLING_TABLE_STRUCTURE", "false").lower() == "true"
DOCLING_DOCUMENT_TIMEOUT = float(os.getenv("DOCLING_DOCUMENT_TIMEOUT", "90"))
DOCLING_NUM_THREADS = int(os.getenv("DOCLING_NUM_THREADS", "1"))
EXTRACTION_ENGINE = os.getenv("EXTRACTION_ENGINE", "auto").lower()
NATIVE_PDF_MIN_CHARS = int(os.getenv("NATIVE_PDF_MIN_CHARS", "40"))
FILE_SUFFIX_BY_CONTENT_TYPE = {
    "application/pdf": ".pdf",
    "image/jpeg": ".jpg",
    "image/png": ".png",
}

_converter = None

def get_converter():
    global _converter
    if _converter is None:
        logger.info(
            "Initializing Docling converter: ocr=%s table_structure=%s timeout=%s num_threads=%s",
            DOCLING_ENABLE_OCR,
            DOCLING_TABLE_STRUCTURE,
            DOCLING_DOCUMENT_TIMEOUT,
            DOCLING_NUM_THREADS,
        )
        from docling.datamodel.accelerator_options import AcceleratorDevice, AcceleratorOptions
        from docling.datamodel.base_models import InputFormat
        from docling.datamodel.pipeline_options import (
            PdfPipelineOptions,
            TableStructureOptions,
            TesseractCliOcrOptions,
        )
        from docling.document_converter import DocumentConverter, PdfFormatOption

        pipeline_options = PdfPipelineOptions()
        pipeline_options.document_timeout = DOCLING_DOCUMENT_TIMEOUT
        pipeline_options.do_ocr = DOCLING_ENABLE_OCR
        pipeline_options.do_table_structure = DOCLING_TABLE_STRUCTURE
        pipeline_options.accelerator_options = AcceleratorOptions(
            num_threads=DOCLING_NUM_THREADS,
            device=AcceleratorDevice.CPU,
        )

        if DOCLING_TABLE_STRUCTURE:
            pipeline_options.table_structure_options = TableStructureOptions(do_cell_matching=True)

        if DOCLING_ENABLE_OCR:
            pipeline_options.ocr_options = TesseractCliOcrOptions(lang=["eng"])

        _converter = DocumentConverter(
            format_options={
                InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_options)
            }
        )
        logger.info("Docling converter initialized")
    return _converter

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
        logger.info(
            "Starting extraction: filename=%s content_type=%s bytes=%s",
            file.filename,
            file.content_type,
            len(content),
        )
        started = time.time()
        extraction_result = _extract_content(content, file.content_type)

        markdown_tables = extraction_result["markdown"]
        page_count = extraction_result["page_count"]
        job_id = _generate_job_id(file.filename)
        elapsed_seconds = round(time.time() - started, 3)
        logger.info(
            "Extraction completed: filename=%s elapsed_seconds=%s engine=%s status=%s markdown_length=%s",
            file.filename,
            elapsed_seconds,
            extraction_result["engine"],
            extraction_result["status"],
            len(markdown_tables),
        )

        return JSONResponse(
            status_code=200,
            content={
                "tables": markdown_tables,
                "page_count": page_count,
                "job_id": job_id,
                "elapsed_seconds": elapsed_seconds,
                "conversion_status": extraction_result["status"],
                "engine": extraction_result["engine"]
            }
        )
    except Exception as e:
        logger.exception("Extraction failed")
        raise HTTPException(
            status_code=500,
            detail=f"Extraction failed: {str(e)}"
        )

def _extract_content(content, content_type):
    """
    Extract text from native PDFs before invoking Docling.

    The Render smoke test uses programmatic PDFs. Pulling their text layer first
    avoids loading Docling's heavier model stack on small instances, while still
    preserving Docling as the fallback path for scanned documents and images.
    """
    if content_type == "application/pdf" and EXTRACTION_ENGINE in {"auto", "native_pdf"}:
        try:
            native_result = _extract_native_pdf(content)
        except Exception:
            logger.exception("Native PDF extraction failed")
            if EXTRACTION_ENGINE == "native_pdf":
                raise
            native_result = {"markdown": "", "engine": "native_pdf", "page_count": 0, "status": "FAILED"}

        if EXTRACTION_ENGINE == "native_pdf" or len(native_result["markdown"]) >= NATIVE_PDF_MIN_CHARS:
            return native_result
        logger.info(
            "Native PDF extraction returned only %s chars; falling back to Docling",
            len(native_result["markdown"]),
        )

    if EXTRACTION_ENGINE == "native_pdf":
        raise ValueError("Native PDF extraction is only available for application/pdf files")

    doc_result = _convert_document(content, content_type)
    result_status = getattr(doc_result, "status", None)
    return {
        "engine": "docling",
        "markdown": _extract_markdown(doc_result),
        "page_count": _page_count(doc_result),
        "status": str(result_status) if result_status is not None else None,
    }

def _extract_native_pdf(content):
    """Extract the embedded text layer from a PDF with a lightweight parser."""
    from pypdf import PdfReader

    reader = PdfReader(BytesIO(content))
    pages = []
    for page_number, page in enumerate(reader.pages, start=1):
        page_text = page.extract_text() or ""
        if page_text.strip():
            pages.append(f"## Page {page_number}\n\n{page_text.strip()}")

    markdown = "\n\n".join(pages)
    return {
        "engine": "native_pdf",
        "markdown": markdown if markdown.strip() else "No content extracted",
        "page_count": len(reader.pages),
        "status": "SUCCESS" if markdown.strip() else "NO_TEXT_LAYER",
    }

def _convert_document(content, content_type):
    """
    Convert an uploaded document with Docling.

    Docling's documented public API accepts local paths or URLs via
    DocumentConverter.convert(). Writing the upload to a temporary file keeps us
    off unstable internal byte-conversion APIs.
    """
    suffix = FILE_SUFFIX_BY_CONTENT_TYPE.get(content_type, ".pdf")
    temp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
            temp_file.write(content)
            temp_path = Path(temp_file.name)
        return get_converter().convert(temp_path)
    finally:
        if temp_path is not None:
            temp_path.unlink(missing_ok=True)

def _extract_markdown(doc_result):
    """
    Export Docling's structured document as Markdown.

    The downstream normalization prompt expects Markdown table structure. The
    public export API is more stable than walking Docling's internal page and
    element classes.
    """
    document = getattr(doc_result, "document", None)
    if document is None:
        return "No content extracted"
    markdown = document.export_to_markdown()
    return markdown if markdown.strip() else "No content extracted"

def _page_count(doc_result):
    """Return a best-effort page count across Docling result versions."""
    pages = getattr(doc_result, "pages", None)
    if pages is not None:
        return len(pages)

    document = getattr(doc_result, "document", None)
    document_pages = getattr(document, "pages", None)
    if document_pages is None:
        return 1
    return len(document_pages)

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
    return {
        "status": "healthy",
        "port": os.getenv("PORT", "8000"),
        "docling_enable_ocr": DOCLING_ENABLE_OCR,
        "docling_table_structure": DOCLING_TABLE_STRUCTURE,
        "docling_document_timeout": DOCLING_DOCUMENT_TIMEOUT,
        "docling_num_threads": DOCLING_NUM_THREADS,
        "extraction_engine": EXTRACTION_ENGINE,
        "native_pdf_min_chars": NATIVE_PDF_MIN_CHARS
    }

@app.get("/")
async def root():
    """Lightweight root endpoint for platform probes."""
    return {"status": "healthy", "service": "spread-docling-service"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=int(os.getenv("PORT", "8000")))
