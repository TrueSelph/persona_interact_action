import json
import yaml
import streamlit as st
from typing import Any, Dict, List
from jvclient.lib.widgets import app_controls, app_header, app_update_action
from jvclient.lib.utils import call_api, get_reports_payload
from streamlit_router import StreamlitRouter

def render(router: StreamlitRouter, agent_id: str, action_id: str, info: dict) -> None:
    (model_key, module_root) = app_header(agent_id, action_id, info)
    
    with st.expander("Persona Configuration"):
        app_controls(agent_id, action_id)
        app_update_action(agent_id, action_id)
        
    with st.expander("Import parameters", False):
        _render_import_parameters(model_key, agent_id, module_root)
        
    with st.expander("Purge Collection", False):
        _render_purge_collection(model_key, agent_id, module_root)
    
    list_key = f"{model_key}_parameters_list"
    if list_key not in st.session_state:
        st.session_state[list_key] = {}
        
    col1, col2, col3 = st.columns([2, 4, 2])
    
    # Pagination state
    if "current_page" not in st.session_state:
        st.session_state.current_page = 1
    if "per_page" not in st.session_state:
        st.session_state.per_page = 10

    params = {
        "page": st.session_state.current_page,
        "per_page": st.session_state.per_page,
        "agent_id": agent_id,
        "reporting": True,
    }
    result = call_api(
        endpoint="action/walker/persona_interact_action/list_parameters",
        json_data=params,
    )
    if result and result.status_code == 200:
        payload = get_reports_payload(result)
        document_list = payload.get("items", [])
        total_pages = payload.get("total_pages", 1)
        current_page = payload.get("page", 1)

        with col3:
            page_col1, page_col2, page_col3 = st.columns([1, 2, 1])
            with page_col1:
                if payload.get("has_previous", False) and st.button("←", key="prev_page"):
                    st.session_state.current_page = max(1, st.session_state.current_page - 1)
                    st.rerun()
            with page_col2:
                st.markdown(
                    f"**Page {current_page}/{total_pages}**"
                )
            with page_col3:
                if payload.get("has_next", False) and st.button("→", key="next_page"):
                    st.session_state.current_page = min(total_pages, st.session_state.current_page + 1)
                    st.rerun()
        st.markdown("### Agent Parameters")
        for document in document_list:
            st.divider()
            st.markdown(f"**ID:** {document.get('id', 'N/A')}")
            parameter = {}
            enabled = document.get('enabled', True)
            enable = st.checkbox(
                "Enable Parameter",
                value=enabled,
                key = f"enable_{document.get('id')}",
                on_change= call_update_parameters, args = (agent_id, document.get('id'), {"enabled": not enabled}),
                label_visibility="visible"
            )

            parameter['condition'] = st.text_input("Condition", value=document.get('condition', 'N/A'), key=f"condition_{document.get('id')}")
            parameter['response'] = st.text_input("Response", value=document.get('response', 'N/A'), key=f"response_{document.get('id')}")
            parameter['action'] = st.text_input("Action", value=document.get('action', 'N/A'), key=f"action_{document.get('id')}")
            
            if st.button("Save Changes", key=f"save_{document.get('id')}"):
                # Implement the logic to save changes to the backend
                if call_update_parameters(agent_id, document.get('id'), parameter):
                    st.success("Changes saved successfully.")
                else:
                    st.error("Failed to update parameter.")

def _render_import_parameters(model_key: str, agent_id: str, module_root: str) -> None:
    knode_source = st.radio(
        "Choose data source:",
        ("Text input", "Upload file"),
        key=f"{model_key}_parameter_source",
    )

    data_to_import = ""
    uploaded_file = None
    text_import = None
    if knode_source == "Text input":
        text_import = st.text_area(
            "Agent Parameters in YAML or JSON",
            value="",
            height=170,
            key=f"{model_key}_parameter_data",
        )

    if knode_source == "Upload file":
        uploaded_file = st.file_uploader(
            "Upload file (YAML or JSON)",
            type=["yaml", "json"],
            key=f"{model_key}_agent_parameter_upload",
        )

    if st.button("Import", key=f"{model_key}_btn_import_parameters"):
        if uploaded_file:
            try:
                file_content = uploaded_file.read().decode("utf-8")
                if uploaded_file.type == "application/json":
                    data_to_import = json.loads(file_content)
                else:
                    data_to_import = yaml.safe_load(file_content)
            except Exception as e:
                st.error(f"Error loading file: {e}")
        if text_import:
            try:
                # Try JSON first
                data_to_import = json.loads(text_import)
            except json.JSONDecodeError:
                try:
                    # Fallback to YAML
                    data_to_import = yaml.safe_load(text_import)
                except yaml.YAMLError as e:
                    raise ValueError("Input is not valid JSON or YAML.") from e

        if data_to_import:
            result = call_api(
                endpoint="action/walker/persona_interact_action/import_parameters",
                json_data={
                    "agent_id": agent_id,
                    "data": list(data_to_import),
                },
            )
            if result:
                st.success("Agent parameters imported successfully")
            else:
                st.error("Failed to import parameters. Ensure valid YAML/JSON format.")
        else:
            st.error("No data to import. Please provide valid text or upload a file.")

def _render_purge_collection(model_key: str, agent_id: str, module_root: str) -> None:
    purge_key = f"{model_key}_purge_confirmation"
    if purge_key not in st.session_state:
        st.session_state[purge_key] = False

    if not st.session_state[purge_key]:
        if st.button("Delete all parameters", key=f"{model_key}_btn_delete_collection"):
            st.session_state[purge_key] = True
            st.rerun()
    else:
        st.warning(
            "⚠️ Are you ABSOLUTELY sure you want to delete ALL parameters? This action cannot be undone!"
        )
        st.markdown(
            """
            **This will permanently:**
            - Delete all parameters in this collection
            - Remove all associated embeddings
        """
        )

        col1, col2 = st.columns([1, 2])
        with col1:
            if st.button(
                "✅ Confirm Permanent Deletion",
                type="primary",
                key=f"{model_key}_btn_confirm_purge",
            ):
                if call_api(
                    endpoint="action/walker/persona_interact_action/delete_collection",
                    json_data={"agent_id": agent_id},
                ):
                    st.success("Collection purged successfully")
                    st.session_state[model_key]["page"] = 1
                else:
                    st.error("Failed to complete purge.")
                st.session_state[purge_key] = False
                st.rerun()
        with col2:
            if st.button("❌ Cancel", key=f"{model_key}_btn_cancel_purge"):
                st.session_state[purge_key] = False
                st.rerun()

def call_update_parameters(agent_id: str, parameter_id: str, parameter: Dict[str, Any]) -> bool:
    result = call_api(
        endpoint="action/walker/persona_interact_action/update_parameters",
        json_data={
            "agent_id": agent_id,
            "id": parameter_id,
            "data": parameter,
            "reporting": True,
        },
    )
    if result and result.status_code == 200:
        return True
    return False