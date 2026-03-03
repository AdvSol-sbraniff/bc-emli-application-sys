// ==========================
// Interface: Users Table
// ==========================
export interface Users {
  user_id: number;
  role: 'admin' | 'user';
  email: string;
  password: string;
  rag_mode: 'rag_on' | 'rag_off';
  first_nm: string;
  last_nm: string;
  address?: string;
  phone?: string;
  postal_cd?: string;
  active_session_id: number;
  active_model?: string;
  created_dttm: string;
  updated_dttm: string;
}
export interface updateUsers {
  user_id?: number;
  role?: 'admin' | 'user';
  email?: string;
  password?: string;
  rag_mode?: 'rag_on' | 'rag_off';
  first_nm?: string;
  last_nm?: string;
  address?: string;
  phone?: string;
  postal_cd?: string;
  active_model?: string;
  active_session_id?: number | null;
}
export interface viewUsers {
  user_id?: number;
  role?: 'admin' | 'user';
  email?: string;
  password?: string;
  rag_mode?: 'rag_on' | 'rag_off';
  first_nm?: string;
  last_nm?: string;
  address?: string;
  phone?: string;
  postal_cd?: string;
  active_session_id?: number;
  active_model?: string;
  session_desc?: string;   
}


// ==========================
// Interface: Auth Tokens Table
// ==========================
export interface auth_tokens {
  token_id: number;
  user_id: number;
  jwt_token: string;
  jti: string;
  issued_at: string;
  expires_at: string;
  created_dttm: string;
  updated_dttm: string;
}

// ==========================
// Interface: Conversations Table
// ==========================
export interface Conversations {
  conversation_id?: number;
  session_id: number;
  user_id: number;
  role: 'user' | 'snow_kb keywords' | 'snow_inc keywords' | 'rag_bid keywords' | 'snow_inc data' | 'upl data' | 'snow_kb data' | 'system' | 'rag_data' | 'assistant';
  content: string;
  upl_filename?: string;   
  rag_filename?: string;   
  rag_chunk_id?: number;            
  rag_tags?: string;          
  api_keywords?: string;   
  snow_sys_id?:  string;
  removed_flag: string;
  token_count?: number;
  created_dttm?: string;
  updated_dttm?: string;
}
export interface updateConversations {
  conversation_id?: number;
  session_id?: number;
  user_id?: number;
  role?: 'user' | 'snow_kb keywords' | 'snow_inc keywords' | 'rag_bid keywords' | 'snow_inc data' | 'upl data' | 'snow_kb data' | 'system' | 'rag_data' | 'assistant';
  content?: string;
  upl_filename?: string;   
  rag_filename?: string;   
  rag_chunk_id?: number;            
  rag_tags?: string;          
  api_keywords?: string;   
  snow_sys_id?:  string;
  removed_flag?: string;
  token_count?: number;
}

// ==========================
// Interface: Sessions Table
// ==========================
export interface Sessions {
  session_id?: number;
  session_owner_user_id: number;
  session_desc?: string;
  session_type?: 'Industry' | 'Corporation' | 'Team' | 'Transaction' | 'AI-Conversation' | 'Misc';
  role_id?: number;
  created_dttm?: string;
  updated_dttm?: string;
}

export interface view_sessions {
  session_id?: number;
  session_owner_user_id: number;
  session_desc?: string;
  session_type?: 'Industry' | 'Corporation' | 'Team' | 'Transaction' | 'AI-Conversation' | 'Misc';
  role_id?: number;
  role_desc?: string;
  created_dttm?: string;
  updated_dttm?: string;
}

export interface view_available_rolesessions {
  user_id: number;
  role_id: number;
  role_desc: string;
  session_id: number | null;
  session_desc: string | null;
  session_type: string | null;
  session_created_dttm: string | null;
  session_updated_dttm: string | null;
}

export interface view_enabled_rolesessions {
  user_id: number;
  session_id: number;
  session_desc: string;
  session_type: string;
  role_id: number;
  role_desc: string;
  seq: number;
  user_rolesession_created_dttm: string;
  session_created_dttm: string;
}

export interface view_user_roles {
  user_role_id: number;
  user_id: number;
  email: string;
  role_id: number;
  role_desc: string;
  user_role_created_dttm: string; // ISO date string, adjust to Date if you're parsing it
}

export interface  QuickPrompts {
  quickprompt_id: number;
  category: string;
  label: string;
  prefill_text: string;
  use_page_count: boolean;
};