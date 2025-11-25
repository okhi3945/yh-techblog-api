import os
import psycopg2 # PostgreSQL 데이터베이스와 통신할 때 필요
from dotenv import load_dotenv # .env 파일에서 환경 변수 가져오기
from flask import Flask, request, jsonify # Flask 웹 프레임워크와 요청, 응답 저치 도구

# 환경 변수 로드
load_dotenv() # 프로젝트 루트에 있는 .env 파일의 내용을 환경 변수로 시스템에 로드

app = Flask(__name__) # Flask 애플리케이션 인스턴스 생성

# DB 연결 정보 설정 (.env 환경 변수 사용)
# 보안을 위해 환경 변수에서 가져옴
DB_HOST = os.getenv("DB_HOST")
DB_NAME = os.getenv("DB_NAME")
DB_USER = os.getenv("DB_USER")
DB_PASSWORD = os.getenv("DB_PASSWORD")

def get_db_connection():
    """ 데이터 베이스 연결 객체를 생성하고 반환하는 함수"""
    try:
        # psycopg2를 사용하여 DB 연결 시도(conn 객체를 만들어서 DB 연결 정보를 넘겨줌)
        conn = psycopg2.connect(
            host=DB_HOST,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD
        )
        return conn
    except Exception as e:
        # 연결 실패 시 로그
        print(f"DB 연결 실패 : {e}")
        return None
def init_db():
    """테이블 없으면 생성, 테이블 생성 및 초기화"""
    conn = get_db_connection() # DB 연결 함수로 연결 시도하기

    if conn is None:
        return # DB 연결 객체가 None (없으면) 함수 종료

    cursor = conn.cursor() # SQL 명령 실행을 위한 커서 객체 생성
    
    # posts 테이블이 존재하지 않을때만 테이블 생성 SQL 문
    create_table_query = """
    CREATE TABLE IF NOT EXISTS posts (
        id SERIAL PRIMARY KEY, --- 게시글 고유 ID (시리얼이기 때문에 자동 증가)
        title VARCHAR(100) NOT NULL, --- 제목 (100자 제한으로 필수값)
        content TEXT NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP --- 생성 시간 (기본값으로 현재시간)
        );
    """

    try:
        cursor.execute(create_table_query) # 커서 객체 사용하여 SQL 쿼리 실행
        conn.commit() # 변경 사항 DB에 반영하여 커밋 (테이블 생성)
    except Exception as e:
        print(f"DB 생성 오류 : {e}")
    finally:
        cursor.close() # 사용 후 커서 닫기
        conn.close() # DB 연결 끊기

# with 키워드를 사용하여 Flask 앱 컨텍스트 내에서 실행됨 보장
# 애플리케이션 시작될 때 DB 초기화 함수 한 번 실행함
with app.app_context():
    init_db()

# API 엔드포인트, CRUD 구현
@app.route('/posts', methods=['POST'])
def create_post():
    """ 새 게시글 생성하는 API (C) """
    data = request.get_json() # 클라이언트가 보낸 JSON 데이터 파싱
    title = data.get('title') # title로 보내진 data를 title 변수로 가져오기
    content = data.get('content') # 위와 같음

    if not title or not content: # 제목이나 내용 없을 경우 오류 메시지 반환
        return jsonify({"error": "제목, 내용이 없어서 오류"}), 400

    conn = get_db_connection() # db 연결 함수로 db 객체 가져오기
    if conn is None: return jsonify({"error": "DB 연결이 실패함"}), 500 # 연결 실패 시 500 에러

    cursor = conn.cursor()
    try:
        # DB에 제목, 내용을 삽입하는 쿼리 실행
        cursor.execute(
            "INSERT INTO posts (title, content) VALUES (%s, %s) RETURNING id;",
            (title, content)
        )
        post_id = cursor.fetchone()[0] # 반환된 ID를 가져옴
        conn.commit() # 변경 사항을 확정
        # HTTP 201 Created 응답과 함께 생성된 ID를 반환
        return jsonify({"message": "게시물 생성됨", "id": post_id}), 201
    except Exception as e:
        conn.rollback() # 오류 발생 시 변경 사항을 취소합니다.
        return jsonify({"error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()


@app.route('/posts', methods=['GET'])
def get_posts():
    """모든 게시글을 조회하는 API (R)"""
    conn = get_db_connection()
    if conn is None: return jsonify({"error": "DB 연결 실패"}), 500

    cursor = conn.cursor()
    try:
        # 모든 게시글을 최신 순으로 조회
        cursor.execute("SELECT id, title, content, created_at FROM posts ORDER BY created_at DESC;")
        posts = cursor.fetchall() # 모든 결과를 리스트 형태로 가져오기

        # 커서의 description을 사용하여 컬럼 이름(title, content 등) 가져옴
        columns = [desc[0] for desc in cursor.description]
        # 조회된 데이터와 컬럼 이름을 매핑하여 JSON 형식에 맞게 리스트로 변환
        results = [dict(zip(columns, row)) for row in posts]

        return jsonify(results) # JSON 응답 반환
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()


@app.route('/posts/<int:post_id>', methods=['GET'])
def get_post(post_id):
    """특정 ID의 게시글을 상세 조회하는 API (R1)"""
    conn = get_db_connection()
    if conn is None: return jsonify({"error": "DB 연결 실패"}), 500

    cursor = conn.cursor()
    try:
        # 특정 ID에 해당하는 게시글을 조회합니다. %s 사용
        cursor.execute("SELECT id, title, content, created_at FROM posts WHERE id = %s;", (post_id,))
        post = cursor.fetchone() # 결과 중 첫 번째 행만 가져오기

        if post is None:
            # 해당 ID의 게시글이 없으면 HTTP 404 Not Found 응답을 반환
            return jsonify({"error": "게시물을 찾을 수 없음"}), 404

        # 결과를 JSON 형태로 변환
        columns = [desc[0] for desc in cursor.description]
        result = dict(zip(columns, post))

        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()


@app.route('/posts/<int:post_id>', methods=['PUT'])
def update_post(post_id):
    """특정 게시글 수정 (U)"""
    data = request.get_json()
    title = data.get('title')
    content = data.get('content')

    if not title or not content:
        return jsonify({"error": "수정할 게시글과 내용을 입력하세요"}), 400

    conn = get_db_connection()
    if conn is None: return jsonify({"error": "연결 실패"}), 500

    cursor = conn.cursor()
    try:
        # 게시글을 수정하는 쿼리 실행
        cursor.execute(
            "UPDATE posts SET title = %s, content = %s WHERE id = %s;",
            (title, content, post_id)
        )
        # 몇 개의 행이 업데이트 되었는지 확인
        if cursor.rowcount == 0:
            conn.rollback()
            return jsonify({"error": "게시글을 찾을 수 없음"}), 404
        
        conn.commit()
        return jsonify({"message": f"게시글 {post_id}이 성공적으로 수정됨"}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()


@app.route('/posts/<int:post_id>', methods=['DELETE'])
def delete_post(post_id):
    """특정 게시글 삭제 (D)"""
    conn = get_db_connection()
    if conn is None: return jsonify({"error": "DB 연결 실패"}), 500

    cursor = conn.cursor()
    try:
        # 게시글을 삭제하는 쿼리 실행
        cursor.execute("DELETE FROM posts WHERE id = %s;", (post_id,))
        
        # 몇 개의 행이 삭제되었는지 확인
        if cursor.rowcount == 0:
            conn.rollback()
            return jsonify({"error": "게시물 찾을 수 없음"}), 404
        
        conn.commit()
        return jsonify({"message": f"게시물 {post_id}이 삭제됨"}), 200
    except Exception as e:
        conn.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        cursor.close()
        conn.close()


if __name__ == '__main__':
    port = int(os.getenv('FLASK_RUN_PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=True)
