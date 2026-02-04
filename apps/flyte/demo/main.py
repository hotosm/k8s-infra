import os
import pandas as pd

from sklearn.datasets import load_wine
from sklearn.linear_model import LogisticRegression
# from flytekit import ImageSpec
from flytekit import task, workflow, Resources


# Set the Flyte API URL (in prod we handle this automatically)
# For local dev:
# kubectl port-forward svc/flyteadmin -n flyte 8083:80
os.environ["FLYTE_PLATFORM_URL"] = "http://localhost:8083"
os.environ["FLYTE_PLATFORM_INSECURE"] = "True"
os.environ["FLYTE_DEFAULT_PROJECT"] = "fAIr"
os.environ["FLYTE_DEFAULT_DOMAIN"] = "development"

# Using ImageSpec allows us to customize and existing image
# (essentially removing the requirement for the dev to build a Dockerfile)
#
# However, we plan to include a Dockerfile build as part of the fAIr
# PR testing / validation when users submit new models.
#
# image_spec = ImageSpec(
#     base_image="nvidia/cuda:12.6.1-cudnn-devel-ubuntu22.04",
#     platform="linux/amd64", # change to arm64 as needed
#     packages=["tensorflow", "pandas"],
#     python_version="3.12",
#     registry="ghcr.io/hotosm",
#     name="wine-classification-image",
#     # alternatively load from requirements file
#     # requirements="image-requirements.txt"
# )
image_spec = "ghcr.io/hotosm/fair-models/flyte-demo:latest"


@task(container_image=image_spec, requests=Resources(mem="700Mi"))
def get_data() -> pd.DataFrame:
    """Get the wine dataset."""
    return load_wine(as_frame=True).frame


@task(container_image=image_spec)
def process_data(data: pd.DataFrame) -> pd.DataFrame:
    """Simplify the task from a 3-class to a binary classification problem."""
    return data.assign(target=lambda x: x["target"].where(x["target"] == 0, 1))


@task(container_image=image_spec)
def train_model(data: pd.DataFrame, hyperparameters: dict) -> LogisticRegression:
    """Train a model on the wine dataset."""
    features = data.drop("target", axis="columns")
    target = data["target"]
    return LogisticRegression(max_iter=3000, **hyperparameters).fit(features, target)


@workflow
def training_workflow(hyperparameters: dict = {"C": 0.1}) -> LogisticRegression:
    """Put all of the steps together into a single workflow."""
    data = get_data()
    processed_data = process_data(data=data)
    return train_model(
        data=processed_data,
        hyperparameters=hyperparameters,
    )
