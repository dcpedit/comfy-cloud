# 📋 ComfyUI Model Checklist for AWS Deployment

## Required Models for VibeVoice + InfiniteTalk Workflows

### ✅ Found in your `C:/ComfyUI/models/` directory:

#### 📂 clip_vision/
- ✅ `clip_vision_h.safetensors`

#### 📂 vae/
- ✅ `Wan2_1_VAE_bf16.safetensors`

#### 📂 text_encoders/
- ✅ `umt5-xxl-enc-bf16.safetensors`

#### 📂 loras/
- ✅ `lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors`

#### 📂 diffusion_models/
- ✅ `wan2.1-i2v-14b-480p-Q8_0.gguf` (WAN 2.1 I2V model)
- ✅ `Wan2_1-InfiniteTalk_Single_Q8.gguf` (InfiniteTalk model)
- ✅ `MelBandRoformer_fp16.safetensors` (Audio separation)
- ✅ `lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors` (LoRA as safetensors)

#### 📂 transformers/
- ✅ `TencentGameMate/chinese-wav2vec2-base/` (Hugging Face model directory)

#### 📂 vibevoice/
- ✅ Auto-downloaded from Hugging Face when first used

## 🚀 Upload Instructions

### Option 1: Upload all models at once (Recommended)
```bash
python upload_models_to_s3.py
# When prompted for ComfyUI models directory, just press Enter
# (script defaults to C:/ComfyUI/models)
```

### Option 2: Manual verification
Check each directory exists and contains the required files:

```bash
# Verify your models are present
ls "C:/ComfyUI/models/clip_vision/clip_vision_h.safetensors"
ls "C:/ComfyUI/models/vae/Wan2_1_VAE_bf16.safetensors"
ls "C:/ComfyUI/models/text_encoders/umt5-xxl-enc-bf16.safetensors"
ls "C:/ComfyUI/models/loras/lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors"
ls "C:/ComfyUI/models/diffusion_models/wan2.1-i2v-14b-480p-Q8_0.gguf"
ls "C:/ComfyUI/models/diffusion_models/Wan2_1-InfiniteTalk_Single_Q8.gguf"
ls "C:/ComfyUI/models/diffusion_models/MelBandRoformer_fp16.safetensors"
ls "C:/ComfyUI/models/transformers/TencentGameMate/chinese-wav2vec2-base/"
```

## 📁 Final S3 Structure
After upload, your S3 bucket should have:
```
s3://comfyui-models-dp/comfyui/models/
├── clip_vision/
│   └── clip_vision_h.safetensors
├── vae/
│   └── Wan2_1_VAE_bf16.safetensors
├── text_encoders/
│   └── umt5-xxl-enc-bf16.safetensors
├── loras/
│   └── lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors
├── diffusion_models/
│   ├── wan2.1-i2v-14b-480p-Q8_0.gguf
│   ├── Wan2_1-InfiniteTalk_Single_Q8.gguf
│   ├── MelBandRoformer_fp16.safetensors
│   └── lightx2v_I2V_14B_480p_cfg_step_distill_rank64_bf16.safetensors
├── transformers/
│   └── TencentGameMate/
│       └── chinese-wav2vec2-base/
└── vibevoice/
    └── (auto-downloaded during inference)
```

## ⚠️ Important Notes

1. **Hugging Face Models**: The `TencentGameMate/chinese-wav2vec2-base` model will auto-download on first use, but uploading your local copy will save time.

2. **VibeVoice Models**: These auto-download from `microsoft/VibeVoice-1.5B` on first use.

3. **Total Size**: Your model directory is approximately 20-30GB. Ensure you have adequate S3 storage and transfer quota.

4. **Upload Time**: Initial upload may take 1-2 hours depending on internet speed.

## 🔧 After Upload

Update your `entrypoint.sh` to sync from your S3 bucket:
```bash
aws s3 sync s3://comfyui-models-dp/comfyui/models /app/ComfyUI/models
```

## ✅ Verification

After deployment, check that models are loading correctly in the container logs:
- Look for successful model loading messages
- Verify no "model not found" errors
- Test both workflows end-to-end