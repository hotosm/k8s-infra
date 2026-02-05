import flyte
import pandas as pd

from sklearn.datasets import load_wine
from sklearn.linear_model import LogisticRegression


env = flyte.TaskEnvironment(
    name="hello_world",
    # resources=flyte.Resources(cpu=1, memory="250Mi", gpu=1),
    resources=flyte.Resources(cpu=1, memory="250Mi"),
    # NOTE
    # This approach allows us to customize an existing image
    # (essentially removing the requirement for the dev to build a Dockerfile)
    # However, we plan to include a Dockerfile build as part of the fAIr
    # PR testing / validation when users submit new models.
    # NOTE
    # image=flyte.Image.from_debian_base().with_pip_packages(
    #     "torch", "pandas", "scikit-learn"
    # ),
    image="ghcr.io/hotosm/fair-models/flyte-demo:latest",
)


@env.task
def get_data() -> pd.DataFrame:
    """Get the wine dataset."""
    return load_wine(as_frame=True).frame


@env.task
def process_data(data: pd.DataFrame) -> pd.DataFrame:
    """Simplify the task from a 3-class to a binary classification problem."""
    return data.assign(target=lambda x: x["target"].where(x["target"] == 0, 1))


@env.task
def train_model(data: pd.DataFrame, hyperparameters: dict) -> LogisticRegression:
    """Train a model on the wine dataset."""
    features = data.drop("target", axis="columns")
    target = data["target"]
    return LogisticRegression(max_iter=3000, **hyperparameters).fit(features, target)


@env.task
def training_workflow(hyperparameters: dict = {"C": 0.1}) -> LogisticRegression:
    """Put all of the steps together into a single workflow."""
    data = get_data()
    processed_data = process_data(data=data)
    return train_model(
        data=processed_data,
        hyperparameters=hyperparameters,
    )


if __name__ == "__main__":
    # Set the Flyte API URL (in prod we handle this automatically)
    # For local dev:
    # kubectl port-forward service/flyte-flyte-binary-http -n flyte 8090:8090
    flyte.init(
        endpoint="dns://localhost:8090",
        project="fAIr",
        domain="development",
        insecure=True,
        insecure_skip_verify=True,
    )
    run = flyte.run(training_workflow, hyperparameters={"C": 0.1})
    print(f"Result: {run.result}")
    print(f"View at: {run.url}")
