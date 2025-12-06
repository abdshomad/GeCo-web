// Global state
let imageFile = null;
let image = null;
let canvas = null;
let ctx = null;
let resultCanvas = null;
let resultCtx = null;
let boundingBoxes = [];
let isDrawing = false;
let startX = 0;
let startY = 0;
let currentBox = null;

// Zoom and pan state
let zoom = 1.0;
let panX = 0;
let panY = 0;
let isPanning = false;
let panStartX = 0;
let panStartY = 0;
let baseCanvasWidth = 0;
let baseCanvasHeight = 0;

// Initialize
document.addEventListener('DOMContentLoaded', () => {
    canvas = document.getElementById('imageCanvas');
    ctx = canvas.getContext('2d');
    resultCanvas = document.getElementById('resultCanvas');
    resultCtx = resultCanvas.getContext('2d');
    
    setupEventListeners();
    checkHealth();
    loadSampleImages();
});

function setupEventListeners() {
    // File upload
    const imageInput = document.getElementById('imageInput');
    const uploadArea = document.getElementById('uploadArea');
    
    imageInput.addEventListener('change', handleImageUpload);
    uploadArea.addEventListener('dragover', (e) => {
        e.preventDefault();
        uploadArea.style.background = '#e9ecef';
    });
    uploadArea.addEventListener('dragleave', () => {
        uploadArea.style.background = '#f8f9fa';
    });
    uploadArea.addEventListener('drop', (e) => {
        e.preventDefault();
        uploadArea.style.background = '#f8f9fa';
        const files = e.dataTransfer.files;
        if (files.length > 0 && files[0].type.startsWith('image/')) {
            imageInput.files = files;
            handleImageUpload({ target: { files: files } });
        }
    });
    
    // Canvas drawing and zoom/pan
    canvas.addEventListener('mousedown', handleMouseDown);
    canvas.addEventListener('mousemove', handleMouseMove);
    canvas.addEventListener('mouseup', handleMouseUp);
    canvas.addEventListener('mouseleave', handleMouseUp);
    canvas.addEventListener('wheel', handleWheel, { passive: false });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault()); // Disable right-click menu
    
    // Zoom controls
    document.getElementById('zoomIn').addEventListener('click', () => setZoom(zoom * 1.2));
    document.getElementById('zoomOut').addEventListener('click', () => setZoom(zoom / 1.2));
    document.getElementById('zoomReset').addEventListener('click', resetZoom);
    
    // Controls
    document.getElementById('clearBoxes').addEventListener('click', clearAllBoxes);
    document.getElementById('undoBox').addEventListener('click', undoLastBox);
    document.getElementById('runInference').addEventListener('click', runInference);
}

async function checkHealth() {
    try {
        const response = await fetch('/api/health');
        const data = await response.json();
        if (!data.model_loaded) {
            showError('Model is not loaded. Please ensure GeCo.pth is available.');
        }
    } catch (error) {
        console.error('Health check failed:', error);
    }
}

async function loadSampleImages() {
    try {
        const response = await fetch('/api/sample-images');
        const data = await response.json();
        const images = data.images || [];
        
        const grid = document.getElementById('sampleImagesGrid');
        
        if (images.length === 0) {
            grid.innerHTML = '<div class="loading-samples">No sample images available</div>';
            return;
        }
        
        grid.innerHTML = '';
        
        images.forEach(image => {
            const item = document.createElement('div');
            item.className = 'sample-image-item';
            item.innerHTML = `
                <img src="${image.url}" alt="${image.name}" loading="lazy">
                <div class="sample-name">${image.name}</div>
            `;
            item.addEventListener('click', () => loadSampleImage(image));
            grid.appendChild(item);
        });
    } catch (error) {
        console.error('Failed to load sample images:', error);
        const grid = document.getElementById('sampleImagesGrid');
        grid.innerHTML = '<div class="loading-samples">Failed to load sample images</div>';
    }
}

async function loadSampleImage(imageInfo) {
    try {
        // Fetch the image
        const response = await fetch(imageInfo.url);
        const blob = await response.blob();
        
        // Create a File object from the blob
        const file = new File([blob], imageInfo.name, { type: blob.type });
        
        // Create a FileList-like object
        const dataTransfer = new DataTransfer();
        dataTransfer.items.add(file);
        
        // Set the file input
        const imageInput = document.getElementById('imageInput');
        imageInput.files = dataTransfer.files;
        
        // Trigger the upload handler
        handleImageUpload({ target: { files: dataTransfer.files } });
        
        // Update file name display
        document.getElementById('fileName').textContent = imageInfo.name;
    } catch (error) {
        showError(`Failed to load sample image: ${error.message}`);
    }
}

function handleImageUpload(event) {
    const file = event.target.files[0];
    if (!file) return;
    
    if (!file.type.startsWith('image/')) {
        showError('Please upload a valid image file.');
        return;
    }
    
    imageFile = file;
    document.getElementById('fileName').textContent = file.name;
    
    const reader = new FileReader();
    reader.onload = (e) => {
        image = new Image();
        image.onload = () => {
            displayImage();
            document.getElementById('canvasSection').style.display = 'block';
            document.getElementById('settingsSection').style.display = 'block';
            document.getElementById('actionSection').style.display = 'block';
            document.getElementById('resultsSection').style.display = 'none';
            boundingBoxes = [];
        };
        image.src = e.target.result;
    };
    reader.readAsDataURL(file);
}

function displayImage() {
    // Set canvas size
    const maxWidth = 800;
    const maxHeight = 600;
    let width = image.width;
    let height = image.height;
    
    if (width > maxWidth) {
        height = (height * maxWidth) / width;
        width = maxWidth;
    }
    if (height > maxHeight) {
        width = (width * maxHeight) / height;
        height = maxHeight;
    }
    
    baseCanvasWidth = width;
    baseCanvasHeight = height;
    canvas.width = width;
    canvas.height = height;
    
    // Reset zoom and pan
    resetZoom();
}

// Convert canvas coordinates to image coordinates accounting for zoom/pan
function canvasToImage(x, y) {
    const imgX = (x - panX) / zoom;
    const imgY = (y - panY) / zoom;
    return { x: imgX, y: imgY };
}

// Convert image coordinates to canvas coordinates accounting for zoom/pan
function imageToCanvas(imgX, imgY) {
    const x = imgX * zoom + panX;
    const y = imgY * zoom + panY;
    return { x, y };
}

function handleMouseDown(e) {
    const rect = canvas.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;
    
    // Right mouse button or middle button for panning
    if (e.button === 2 || e.button === 1 || e.ctrlKey || e.metaKey) {
        isPanning = true;
        panStartX = mouseX - panX;
        panStartY = mouseY - panY;
        canvas.style.cursor = 'grabbing';
        return;
    }
    
    // Left mouse button for drawing
    if (boundingBoxes.length >= 10) {
        alert('Maximum 10 bounding boxes allowed');
        return;
    }
    
    isDrawing = true;
    const imgCoords = canvasToImage(mouseX, mouseY);
    startX = imgCoords.x;
    startY = imgCoords.y;
    
    currentBox = {
        x: startX,
        y: startY,
        width: 0,
        height: 0
    };
}

function handleMouseMove(e) {
    const rect = canvas.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;
    
    if (isPanning) {
        panX = mouseX - panStartX;
        panY = mouseY - panStartY;
        redrawCanvas();
        return;
    }
    
    if (!isDrawing) {
        canvas.style.cursor = 'crosshair';
        return;
    }
    
    const imgCoords = canvasToImage(mouseX, mouseY);
    currentBox.width = imgCoords.x - startX;
    currentBox.height = imgCoords.y - startY;
    
    redrawCanvas();
    
    // Draw current box
    drawBox(currentBox, 'rgba(255, 0, 0, 0.5)', true);
}

function handleMouseUp(e) {
    if (isPanning) {
        isPanning = false;
        canvas.style.cursor = 'crosshair';
        return;
    }
    
    if (!isDrawing) return;
    isDrawing = false;
    
    if (Math.abs(currentBox.width) > 5 / zoom && Math.abs(currentBox.height) > 5 / zoom) {
        // Normalize box coordinates (already in image coordinates)
        const x1 = Math.min(startX, startX + currentBox.width);
        const y1 = Math.min(startY, startY + currentBox.height);
        const x2 = Math.max(startX, startX + currentBox.width);
        const y2 = Math.max(startY, startY + currentBox.height);
        
        // Convert to original image coordinates
        const scaleX = image.width / baseCanvasWidth;
        const scaleY = image.height / baseCanvasHeight;
        
        boundingBoxes.push({
            x1: x1 * scaleX,
            y1: y1 * scaleY,
            x2: x2 * scaleX,
            y2: y2 * scaleY
        });
    }
    
    currentBox = null;
    redrawCanvas();
}

function handleWheel(e) {
    e.preventDefault();
    
    const rect = canvas.getBoundingClientRect();
    const mouseX = e.clientX - rect.left;
    const mouseY = e.clientY - rect.top;
    
    // Get image coordinates before zoom
    const imgCoords = canvasToImage(mouseX, mouseY);
    
    // Adjust zoom
    const zoomFactor = e.deltaY > 0 ? 0.9 : 1.1;
    const newZoom = Math.max(0.1, Math.min(5.0, zoom * zoomFactor));
    
    if (newZoom !== zoom) {
        // Adjust pan to zoom towards mouse position
        panX = mouseX - imgCoords.x * newZoom;
        panY = mouseY - imgCoords.y * newZoom;
        zoom = newZoom;
        
        updateZoomDisplay();
        redrawCanvas();
    }
}

function redrawCanvas() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    
    // Save context
    ctx.save();
    
    // Apply zoom and pan transformations
    ctx.translate(panX, panY);
    ctx.scale(zoom, zoom);
    
    // Draw image
    ctx.drawImage(image, 0, 0, baseCanvasWidth, baseCanvasHeight);
    
    // Draw existing boxes (in image coordinates)
    const scaleX = baseCanvasWidth / image.width;
    const scaleY = baseCanvasHeight / image.height;
    
    boundingBoxes.forEach(box => {
        const scaledBox = {
            x: (box.x1 * scaleX),
            y: (box.y1 * scaleY),
            width: ((box.x2 - box.x1) * scaleX),
            height: ((box.y2 - box.y1) * scaleY)
        };
        drawBox(scaledBox, 'rgba(255, 0, 0, 0.3)', false);
    });
    
    // Draw current box if drawing
    if (currentBox) {
        drawBox(currentBox, 'rgba(255, 0, 0, 0.5)', true);
    }
    
    // Restore context
    ctx.restore();
}

function redrawBoxes() {
    redrawCanvas();
}

function drawBox(box, color, isTemporary) {
    // Box coordinates are already in image space due to transform
    ctx.strokeStyle = isTemporary ? 'red' : 'red';
    ctx.lineWidth = 2 / zoom; // Adjust line width for zoom
    ctx.fillStyle = color;
    
    if (isTemporary) {
        ctx.setLineDash([5 / zoom, 5 / zoom]);
    } else {
        ctx.setLineDash([]);
    }
    
    ctx.fillRect(box.x, box.y, box.width, box.height);
    ctx.strokeRect(box.x, box.y, box.width, box.height);
}

function setZoom(newZoom) {
    zoom = Math.max(0.1, Math.min(5.0, newZoom));
    updateZoomDisplay();
    redrawCanvas();
}

function resetZoom() {
    zoom = 1.0;
    panX = 0;
    panY = 0;
    updateZoomDisplay();
    redrawCanvas();
}

function updateZoomDisplay() {
    const zoomLevel = document.getElementById('zoomLevel');
    if (zoomLevel) {
        zoomLevel.textContent = Math.round(zoom * 100) + '%';
    }
}

function clearAllBoxes() {
    boundingBoxes = [];
    redrawBoxes();
}

function undoLastBox() {
    if (boundingBoxes.length > 0) {
        boundingBoxes.pop();
        redrawBoxes();
    }
}

async function runInference() {
    if (!imageFile) {
        showError('Please upload an image first.');
        return;
    }
    
    if (boundingBoxes.length === 0) {
        showError('Please draw at least one bounding box.');
        return;
    }
    
    const loading = document.getElementById('loading');
    const runButton = document.getElementById('runInference');
    const errorSection = document.getElementById('errorSection');
    
    loading.style.display = 'flex';
    runButton.disabled = true;
    errorSection.style.display = 'none';
    
    try {
        // Prepare form data
        const formData = new FormData();
        formData.append('image', imageFile);
        formData.append('bboxes', JSON.stringify(boundingBoxes.map(b => [b.x1, b.y1, b.x2, b.y2])));
        formData.append('output_masks', document.getElementById('outputMasks').checked);
        formData.append('threshold', parseFloat(document.getElementById('threshold').value));
        
        // Send request
        const response = await fetch('/api/infer', {
            method: 'POST',
            body: formData
        });
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.detail || 'Inference failed');
        }
        
        const result = await response.json();
        displayResults(result);
        
    } catch (error) {
        showError(error.message);
    } finally {
        loading.style.display = 'none';
        runButton.disabled = false;
    }
}

function displayResults(result) {
    // Update count
    document.getElementById('objectCount').textContent = result.count;
    
    // Display result image with boxes
    resultCanvas.width = result.image_width;
    resultCanvas.height = result.image_height;
    resultCtx.drawImage(image, 0, 0, resultCanvas.width, resultCanvas.height);
    
    // Draw detected boxes
    result.boxes.forEach((box, index) => {
        const [x1, y1, x2, y2] = box;
        resultCtx.strokeStyle = 'orange';
        resultCtx.lineWidth = 2;
        resultCtx.setLineDash([]);
        resultCtx.strokeRect(x1, y1, x2 - x1, y2 - y1);
        
        // Draw box number
        resultCtx.fillStyle = 'orange';
        resultCtx.font = '14px Arial';
        resultCtx.fillText((index + 1).toString(), x1 + 5, y1 + 18);
    });
    
    // Draw original exemplar boxes
    boundingBoxes.forEach(box => {
        resultCtx.strokeStyle = 'red';
        resultCtx.lineWidth = 3;
        resultCtx.strokeRect(box.x1, box.y1, box.x2 - box.x1, box.y2 - box.y1);
    });
    
    // Display mask if available
    if (result.mask) {
        const maskImg = document.getElementById('maskImage');
        maskImg.src = result.mask;
        document.getElementById('maskContainer').style.display = 'block';
    } else {
        document.getElementById('maskContainer').style.display = 'none';
    }
    
    // Show results section
    document.getElementById('resultsSection').style.display = 'block';
    document.getElementById('resultsSection').scrollIntoView({ behavior: 'smooth' });
}

function showError(message) {
    const errorSection = document.getElementById('errorSection');
    const errorMessage = document.getElementById('errorMessage');
    errorMessage.textContent = message;
    errorSection.style.display = 'block';
    errorSection.scrollIntoView({ behavior: 'smooth' });
}

