"""Model loading and management module"""
import torch
from torch.nn import DataParallel
import os
import argparse
from models.geco_infer import build_model
from utils.arg_parser import get_argparser


class ModelManager:
    """Manages the GeCo model lifecycle"""
    
    def __init__(self):
        self.model = None
        self.device = None
        self.args = None
    
    def load_model(self, model_path: str = None):
        """Load the GeCo model"""
        if self.model is not None:
            return
        
        # Set up arguments
        parser = argparse.ArgumentParser('GeCo', parents=[get_argparser()])
        self.args = parser.parse_args([])
        
        # Set model path
        if model_path is None:
            model_path = os.getenv('MODEL_PATH', 'GeCo.pth')
        
        # Try common locations if file doesn't exist in current directory
        if not os.path.exists(model_path):
            # Try in current directory
            if not os.path.isabs(model_path):
                # Try common alternative locations
                possible_paths = [
                    model_path,  # Original path
                    f'./{model_path}',  # Explicit current dir
                    f'./models/{model_path}',  # In models directory
                    f'./MODEL_folder/{model_path}',  # As mentioned in README
                ]
                
                for path in possible_paths:
                    if os.path.exists(path):
                        model_path = path
                        break
                else:
                    # None of the paths exist
                    raise FileNotFoundError(
                        f"Model file not found: {model_path}\n"
                        f"Please ensure the model file exists. Common locations:\n"
                        f"  - {model_path}\n"
                        f"  - ./models/{model_path}\n"
                        f"  - ./MODEL_folder/{model_path}\n"
                        f"Or set MODEL_PATH environment variable or in .env file"
                    )
        
        # Set device
        gpu = 0
        if torch.cuda.is_available():
            torch.cuda.set_device(gpu)
            self.device = torch.device(gpu)
        else:
            self.device = torch.device('cpu')
        
        # Build and load model
        self.model = DataParallel(
            build_model(self.args).to(self.device),
            device_ids=[gpu] if torch.cuda.is_available() else [],
            output_device=gpu if torch.cuda.is_available() else None
        )
        
        state_dict = torch.load(model_path, map_location=self.device, weights_only=True)
        if 'model' in state_dict:
            self.model.load_state_dict(state_dict['model'], strict=False)
        else:
            self.model.load_state_dict(state_dict, strict=False)
        
        self.model.eval()
        print(f"Model loaded successfully on {self.device}")
    
    def is_loaded(self):
        """Check if model is loaded"""
        return self.model is not None
    
    def get_model(self):
        """Get the loaded model"""
        if self.model is None:
            raise RuntimeError("Model not loaded. Call load_model() first.")
        return self.model
    
    def get_device(self):
        """Get the device"""
        if self.device is None:
            raise RuntimeError("Model not loaded. Call load_model() first.")
        return self.device


# Global model manager instance
_model_manager = ModelManager()


def get_model_manager():
    """Get the global model manager instance"""
    return _model_manager

